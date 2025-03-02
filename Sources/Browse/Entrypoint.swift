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

  mutating func run() async {
    do {
      var server = Server(
        port: port,
        dbPath: dbPath,
        modelPath: modelPath,
        featureDir: featureDir,
        clusterPath: clusterPath
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

  var app: Application! = nil
  var db: DB! = nil
  var neighbors: Neighbors! = nil

  mutating func setup() async throws {
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

    print("creating neighbors...")
    neighbors = try await Neighbors(featureDir: featureDir, clusterPath: clusterPath)

    setupImageRoute()
    setupNameRoute()
    setupRedirectRoute()
    setupNeighborRoutes()
  }

  func setupFileRoutes() throws {
    let filenames = ["index.html", "app.js"]
    let contentTypes = ["html": "text/html", "js": "text/javascript"]
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
      let imageData = await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
          continuation.resume(returning: try? db.getProductImage(id: productID))
        }
      }
      guard let imageData = imageData else {
        return Response(status: .notFound)
      }
      return Response(
        status: .ok,
        headers: ["content-type": "image/jpeg"],
        body: .init(data: imageData)
      )
    }
  }

  func setupNameRoute() {
    let db = db!
    app.on(.GET, "productName") { request -> Response in
      guard let productID = request.query[String.self, at: "id"] else {
        return Response(status: .badRequest)
      }
      guard let row = try? db.getProduct(id: productID) else {
        return Response(status: .notFound)
      }
      return Response(
        status: .ok,
        headers: ["content-type": "text/plain"],
        body: .init(data: (row[db.fields.name] ?? "<unknown name>").data(using: .utf8) ?? Data())
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

    app.on(.GET, "firstPage") { request -> Response in
      return Response(
        status: .ok,
        headers: ["content-type": "application/json"],
        body: .init(data: try! JSONEncoder().encode(neighbors.clusterStart))
      )
    }

    app.on(.GET, "neighbors") { request -> Response in
      guard let productID = request.query[String.self, at: "id"] else {
        return Response(status: .badRequest)
      }
      do {
        let results = try await neighbors.neighbors(
          id: productID,
          strides: [1, 64, 256, 1024, 4096]
        )
        return Response(
          status: .ok,
          headers: ["content-type": "application/json"],
          body: .init(data: try! JSONEncoder().encode(results))
        )
      } catch { return Response(status: .badRequest) }
    }
  }

}
