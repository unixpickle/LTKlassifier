import Foundation
import Honeycrisp
import LTKModel
import SQLite

public enum DataError: Error {
  case noData
  case decodeImage
}

public struct DataIterator: Sequence, IteratorProtocol {

  public enum ImageID: Codable {
    case product(String)
    case ltk(String)

    var id: String {
      switch self {
      case .product(let x): x
      case .ltk(let x): x
      }
    }
  }

  public struct State: Codable {
    public var images: [ImageID]
    public var offset: Int
  }

  // Db fields and tables
  let productsTable = Table("products")
  let productImagesTable = Table("product_images")
  let ltksTable = Table("ltks")
  let ltkImagesTable = Table("ltk_hero_images")
  let idField = SQLite.Expression<String>("id")
  let dataField = SQLite.Expression<Data?>("data")
  let errorField = SQLite.Expression<String?>("error")
  let priceField = SQLite.Expression<Float?>("price")

  let lock: NSLock = NSLock()

  let connection: Connection
  let batchSize: Int
  let imageSize: Int
  var state: State

  public init(dbPath: String, batchSize: Int, imageSize: Int = 224) throws {
    connection = try Connection(dbPath)
    self.batchSize = batchSize
    self.imageSize = imageSize
    self.state = State(images: [], offset: 0)

    for item in try connection.prepare(productImagesTable.filter(dataField != nil)) {
      state.images.append(.product(item[idField]))
    }
    for item in try connection.prepare(ltkImagesTable.filter(dataField != nil)) {
      state.images.append(.ltk(item[idField]))
    }
    // The ids seem to be quasi-random at the beginning, so sorting by ID
    // should be roughly equivalent to shuffling.
    state.images.sort { x, y in x.id < y.id }
  }

  public func splitTrainTest() -> (train: DataIterator, test: DataIterator) {
    var train = self
    var test = self
    train.state.images = train.state.images.filter { !$0.id.starts(with: "0") }
    test.state.images = train.state.images.filter { $0.id.starts(with: "0") }
    return (train: train, test: test)
  }

  public mutating func next() -> (Tensor, [[String: Label]], State)? {
    var batch = [Tensor]()
    var labels = [[String: Label]]()
    for _ in 0..<batchSize {
      do {
        let (img, label) = try nextExample()
        batch.append(img)
        labels.append(label)
      } catch { fatalError("failed to load data: example: \(error)") }
    }
    return (Tensor(stack: batch), labels, state)
  }

  mutating func nextExample() throws -> (Tensor, [String: Label]) {
    while true {
      if state.images.isEmpty { throw DataError.noData }
      let obj = state.images[state.offset % state.images.count]
      do {
        let result =
          switch obj {
          case .ltk(let id): try read(ltk: id)
          case .product(let id): try read(product: id)
          }
        state.offset += 1
        return result
      } catch { state.images.remove(at: state.offset % state.images.count) }
    }
  }

  func read(ltk: String) throws -> (Tensor, [String: Label]) {
    let imageData = try lock.withLock {
      let it = try connection.prepare(ltkImagesTable.filter(idField == ltk))
      return it.makeIterator().next()![dataField]!
    }
    guard let imgTensor = loadImage(imageData, imageSize: imageSize) else {
      throw DataError.decodeImage
    }
    return (imgTensor, [:])
  }

  func read(product: String) throws -> (Tensor, [String: Label]) {
    let imageData = try lock.withLock {
      let it = try connection.prepare(productImagesTable.filter(idField == product))
      return it.makeIterator().next()![dataField]!
    }
    guard let imgTensor = loadImage(imageData, imageSize: imageSize) else {
      throw DataError.decodeImage
    }
    return (imgTensor, [:])
  }
}
