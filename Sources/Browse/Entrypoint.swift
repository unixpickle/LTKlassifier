import ArgumentParser
import Foundation
import HCBacktrace
import Honeycrisp
import ImageUtils
import LTKData
import LTKLabel
import LTKModel
import Vapor

enum ServerError: Error {
  case missingResource(String)
  case loadResource(String)
}

@main struct Browse: AsyncParsableCommand {

  @ArgumentParser.Option(name: .shortAndLong, help: "Port to listen on.") var port: Int
  @ArgumentParser.Option(name: .long, help: "Path to database.") var dbPath: String
  @ArgumentParser.Option(name: .long, help: "Path to load the model from.") var modelPath: String =
    "model_state.plist"
  @ArgumentParser.Option(name: .long, help: "Directory to load shards from.") var featureDir:
    String = "features"
  @ArgumentParser.Option(name: .long, help: "Path to save clusters.") var clusterPath: String =
    "clusters.plist"
  // Rate limiting
  @ArgumentParser.Option(
    name: .long,
    help: "Number of reverse proxies that this server sits behind."
  ) var proxyCount: Int = 0
  @ArgumentParser.Option(
    name: .long,
    help: "Maximum number of calls to the neighbors endpoint in an hour."
  ) var maxNeighborsPerHour: Int = 1000

  mutating func run() async {
    do {
      var server = Server(
        port: port,
        dbPath: dbPath,
        modelPath: modelPath,
        featureDir: featureDir,
        clusterPath: clusterPath,
        proxyCount: proxyCount,
        maxNeighborsPerHour: maxNeighborsPerHour
      )
      try await server.setup()
      try await server.app.execute()
    } catch { print("fatal error: \(error)") }
  }

}

public struct Server {

  struct State: Codable { var model: Trainable.State }

  var port: Int
  var dbPath: String
  var modelPath: String
  var featureDir: String
  var clusterPath: String
  var proxyCount: Int
  var maxNeighborsPerHour: Int

  var app: Application! = nil
  var db: DB! = nil
  var neighbors: Neighbors! = nil
  var neighborRateLimiter: RateLimiter! = nil
  var allPrices: [String: Double]! = nil

  mutating func setup() async throws {
    neighborRateLimiter = await RateLimiter(maxPerHour: Double(maxNeighborsPerHour))

    app = try await Application.make(.detect(arguments: ["browse"]))
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = port

    try setupFileRoutes()

    Backend.defaultBackend = try MPSBackend(allocator: .bucket)

    print("creating model...")
    let model = Model(labels: LabelDescriptor.allLabels)

    print("loading from checkpoint: \(modelPath) ...")
    let data = try Data(contentsOf: URL(fileURLWithPath: modelPath))
    let decoder = PropertyListDecoder()
    let loadedState = try decoder.decode(State.self, from: data)
    try model.reconfigureAndLoad(loadedState.model)

    print("creating DB...")
    db = DB(pool: ConnectionPool(path: dbPath))

    print("listing all prices...")
    allPrices = try db.getProductPrices()

    print("creating neighbors...")
    neighbors = try await Neighbors(featureDir: featureDir, clusterPath: clusterPath)

    setupImageRoute()
    setupNameRoute()
    setupRedirectRoute()
    setupNeighborRoutes()
  }

  var getRemoteHost: @Sendable (Request) -> String {
    { [proxyCount] request in
      if proxyCount == 0 { return request.remoteAddress?.ipAddress ?? "" }
      let forwarded = (request.headers["X-Forwarded-For"]).flatMap {
        $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      }
      if forwarded.count < proxyCount {
        print("invalid number of proxies")
        return forwarded.first ?? ""
      }
      return forwarded[forwarded.count - proxyCount]
    }
  }

  func setupFileRoutes() throws {
    let filenames = ["index.html", "app.js", "style.css"]
    let contentTypes = ["html": "text/html", "js": "text/javascript", "css": "text/css"]
    for filename in filenames {
      let parts = filename.split(separator: ".")
      guard
        let url = Bundle.module.url(forResource: String(parts[0]), withExtension: String(parts[1]))
      else { throw ServerError.missingResource(filename) }
      guard let contents = try? Data(contentsOf: url) else {
        throw ServerError.loadResource(filename)
      }
      app.on(.GET, filename == "index.html" ? "" : "\(filename)") { request -> Response in
        Response(
          status: .ok,
          headers: ["content-type": contentTypes[String(parts[1])]!],
          body: .init(data: contents)
        )
      }
    }
  }

  func setupImageRoute() {
    let db = db!
    app.on(.GET, "productImage") { request -> Response in
      guard let productID = request.query[String.self, at: "id"] else {
        return Response(status: .badRequest)
      }
      let isPreview = (request.query[String.self, at: "preview"] ?? "0") == "1"
      let imageData: Data? = await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
          guard let rawData = try? db.getProductImage(id: productID) else {
            continuation.resume(returning: nil)
            return
          }
          if isPreview, let shrunk = shrinkImage(rawData, maxSideLength: 400) {
            continuation.resume(returning: shrunk)
          } else {
            continuation.resume(returning: rawData)
          }
        }
      }
      guard let imageData = imageData else { return Response(status: .notFound) }
      return Response(
        status: .ok,
        headers: ["content-type": "image/jpeg"],
        body: .init(data: imageData)
      )
    }
  }

  func setupNameRoute() {
    let db = db!
    app.on(.GET, "productInfo") { request -> Response in
      guard let productID = request.query[String.self, at: "id"] else {
        return Response(status: .badRequest)
      }
      guard let row = try? db.getProduct(id: productID) else { return Response(status: .notFound) }
      struct Result: Codable {
        let name: String?
        let price: Double?
        let retailer: String?
      }
      let results = Result(
        name: row[db.fields.name],
        price: try? db.productDollarAmount(row),
        retailer: row[db.fields.retailerDisplayName]
      )
      return Response(
        status: .ok,
        headers: ["content-type": "application/json"],
        body: .init(data: try! JSONEncoder().encode(results))
      )
    }
  }

  func setupRedirectRoute() {
    let db = db!
    app.on(.GET, "productRedirect") { request -> Response in
      guard let productID = request.query[String.self, at: "id"] else {
        return Response(status: .badRequest)
      }
      guard let productRow = try? db.getProduct(id: productID) else {
        return Response(status: .notFound)
      }
      let hyperlink = productRow[db.fields.hyperlink]
      return Response(status: .seeOther, headers: ["location": hyperlink])
    }
  }

  func setupNeighborRoutes() {
    let neighbors = neighbors!
    let allPrices = allPrices!
    let rateLimiter = neighborRateLimiter!
    let getRemoteHost = getRemoteHost

    @Sendable func getPrices(_ ids: some Collection<String>) -> [String: Double] {
      var results = [String: Double]()
      for id in ids { if let price = allPrices[id] { results[id] = price } }
      return results
    }

    app.on(.GET, "firstPage") { request -> Response in
      struct Result: Codable {
        let ids: [String]
        let prices: [String: Double]
      }
      let resp = Result(ids: neighbors.clusterStart, prices: getPrices(neighbors.clusterStart))
      return Response(
        status: .ok,
        headers: ["content-type": "application/json"],
        body: .init(data: try! JSONEncoder().encode(resp))
      )
    }

    app.on(.GET, "neighbors") { request -> Response in
      guard let productID = request.query[String.self, at: "id"] else {
        return Response(status: .badRequest)
      }
      let host = getRemoteHost(request)
      if !(await rateLimiter.use(host: host)) { return Response(status: .forbidden) }
      do {
        let n = try await neighbors.neighbors(id: productID, strides: [1, 64, 256, 1024, 4096])
        struct Result: Codable {
          let neighbors: [Int: [String]]
          let prices: [String: Double]
        }
        let resp = Result(neighbors: n, prices: getPrices(Set(n.values.flatMap { $0 })))
        return Response(
          status: .ok,
          headers: ["content-type": "application/json"],
          body: .init(data: try! JSONEncoder().encode(resp))
        )
      } catch { return Response(status: .badRequest) }
    }
  }

}
