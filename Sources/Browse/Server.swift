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

@MainActor public struct Server {

  struct State: Codable { var model: Trainable.State }

  let port: Int
  let dbPath: String
  let modelPath: String
  let featureDir: String
  let clusterPath: String
  let priceOnly: Bool
  let proxyCount: Int
  let maxNeighborsPerHour: Int
  let maxEncodesPerHour: Int

  let app: Application
  let db: DB
  let neighbors: Neighbors
  let modelWrapper: ModelWrapper
  let neighborRateLimiter: RateLimiter
  let neighborSem: KeyedSemaphore<String>
  let encodeRateLimiter: RateLimiter
  let imageSem: KeyedSemaphore<String>
  let allPrices: [String: Double]

  public init(
    port: Int,
    dbPath: String,
    modelPath: String,
    featureDir: String,
    clusterPath: String,
    priceOnly: Bool,
    proxyCount: Int,
    maxNeighborsPerHour: Int,
    maxEncodesPerHour: Int
  ) async throws {
    self.port = port
    self.dbPath = dbPath
    self.modelPath = modelPath
    self.featureDir = featureDir
    self.clusterPath = clusterPath
    self.priceOnly = priceOnly
    self.proxyCount = proxyCount
    self.maxNeighborsPerHour = maxNeighborsPerHour
    self.maxEncodesPerHour = maxEncodesPerHour

    neighborRateLimiter = RateLimiter(maxPerHour: Double(maxNeighborsPerHour))
    neighborSem = KeyedSemaphore(limit: 1)
    encodeRateLimiter = RateLimiter(maxPerHour: Double(maxEncodesPerHour))
    imageSem = KeyedSemaphore(limit: 64, queueLimit: 2048)

    app = try await Application.make(.detect(arguments: ["browse"]))
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = port

    Backend.defaultBackend = try MPSBackend(allocator: .bucket)

    print("creating model...")
    let model = Model(labels: LabelDescriptor.allLabels)
    model.mode = .inference

    print("loading from checkpoint: \(modelPath) ...")
    let data = try Data(contentsOf: URL(fileURLWithPath: modelPath))
    let decoder = PropertyListDecoder()
    let loadedState = try decoder.decode(State.self, from: data)
    try model.reconfigureAndLoad(loadedState.model)

    modelWrapper = ModelWrapper(model: SyncTrainable(model))

    print("creating DB...")
    db = DB(pool: ConnectionPool(path: dbPath))

    print("listing all prices...")
    allPrices = try db.getProductPrices()

    print("creating neighbors...")
    neighbors = try await Neighbors(
      featureDir: featureDir,
      clusterPath: clusterPath,
      whitelist: (priceOnly ? Array(allPrices.keys) : nil)
    )

    try setupFileRoutes()
    setupImageRoute()
    setupNameRoute()
    setupRedirectRoute()
    setupEncodeRoute()
    setupNeighborRoutes()
  }

  nonisolated func getRemoteHost(_ request: Request) -> String {
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

  func setupFileRoutes() throws {
    let filenames = ["index.html", "app.js", "style.css", "favicon.ico", "robots.txt"]
    let contentTypes = [
      "html": "text/html", "js": "text/javascript", "css": "text/css", "ico": "image/x-icon",
      "txt": "text/plain",
    ]
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
    app.on(.GET, "productImage") { request -> Response in
      guard let productID = request.query[String.self, at: "id"] else {
        return Response(status: .badRequest)
      }
      let isPreview = (request.query[String.self, at: "preview"] ?? "0") == "1"
      let host = getRemoteHost(request)
      var imageData: Data? = nil
      do {
        imageData = try await imageSem.use(key: host) {
          await withCheckedContinuation { continuation in
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
        }
      } catch is TooManyConcurrentRequests { return Response(status: .forbidden) }
      guard let imageData = imageData else { return Response(status: .notFound) }
      return Response(
        status: .ok,
        headers: ["content-type": "image/jpeg"],
        body: .init(data: imageData)
      )
    }
  }

  func setupNameRoute() {
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

  func setupEncodeRoute() {
    app.on(.POST, "encode", body: .collect(maxSize: "10mb")) { request -> Response in
      let host = getRemoteHost(request)
      if !(await encodeRateLimiter.use(host: host)) { return Response(status: .forbidden) }

      guard let imageDataBuf = request.body.data else { return Response(status: .badRequest) }
      let imageData = Data(buffer: imageDataBuf)

      guard let imageSize = getImageSize(imageData) else { return Response(status: .badRequest) }
      if imageSize.width > 10000 || imageSize.height > 10000 {
        return Response(status: .badRequest)
      }
      guard let image = loadImage(imageData, imageSize: 224, augment: false, pad: true) else {
        return Response(status: .badRequest)
      }
      let features = modelWrapper.encodeImage(image)
      let floatData = try await features.floats().map { $0.bitPattern.littleEndian }
        .withUnsafeBufferPointer { Data(buffer: $0) }
      let encoded = floatData.base64EncodedString().data(using: .ascii)!
      return Response(
        status: .ok,
        headers: ["content-type": "text/plain"],
        body: .init(data: encoded)
      )
    }
  }

  func setupNeighborRoutes() {
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
      let productID = request.query[String.self, at: "id"]
      let keyword = request.query[String.self, at: "keyword"]
      let features = request.query[String.self, at: "features"]
      if productID == nil && keyword == nil && features == nil {
        return Response(status: .badRequest)
      }

      let host = getRemoteHost(request)
      if !(await neighborRateLimiter.use(host: host)) { return Response(status: .forbidden) }
      do {
        let feature: Tensor =
          if let productID = productID {
            try neighbors.feature(id: productID)
          } else if let keyword = keyword {
            try modelWrapper.feature(keyword: keyword)
          } else if let features = features {
            try decodeFeatureString(features, featureCount: modelWrapper.featureCount)
          } else { fatalError() }
        let n = try await neighborSem.use(key: host) {
          try await neighbors.neighbors(
            feature: feature,
            strides: [1, 64, 256, 1024, 4096],
            dedupAgainstFeature: productID != nil
          )
        }
        let clf = try await modelWrapper.classify(feature: feature)
        struct Result: Codable {
          let neighbors: [Int: [String]]
          let prices: [String: Double]
          let classification: ModelWrapper.Classification
        }
        let resp = Result(
          neighbors: n,
          prices: getPrices(Set(n.values.flatMap { $0 })),
          classification: clf
        )
        return Response(
          status: .ok,
          headers: ["content-type": "application/json"],
          body: .init(data: try! JSONEncoder().encode(resp))
        )
      } catch is TooManyConcurrentRequests { return Response(status: .forbidden) } catch {
        return Response(status: .badRequest)
      }
    }
  }

}

enum FeatureDecodeError: Error {
  case featureIsNotBase64
  case featureIsWrongLength
}

func decodeFeatureString(_ dataStr: String, featureCount: Int) throws -> Tensor {
  guard let rawData = Data(base64Encoded: dataStr) else {
    throw FeatureDecodeError.featureIsNotBase64
  }
  if rawData.count != featureCount * 4 { throw FeatureDecodeError.featureIsWrongLength }
  let floats = rawData.withUnsafeBytes {
    $0.bindMemory(to: UInt32.self).map { Float(bitPattern: UInt32(littleEndian: $0)) }
  }
  return Tensor(data: floats)
}
