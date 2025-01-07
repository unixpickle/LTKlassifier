import Foundation
import Honeycrisp
import LTKLabel
import SQLite

public enum DataError: Error {
  case noData
  case decodeImage
}

public struct DataIterator: Sequence, IteratorProtocol {

  public enum ImageID: Codable, Sendable {
    case product(String)
    case ltk(String)

    var id: String {
      switch self {
      case .product(let x): x
      case .ltk(let x): x
      }
    }

    var sortKey: String {
      // The first component of the UUIDs seem to be quasi-random,
      // so sorting by ID should be roughly equivalent to shuffling.
      //
      // However, the IDs are scraped in order, so there might be a bias
      // in linear ID space towards more downloads at the beginning.
      // To avoid this, we reverse the first component of the ID to avoid
      // this bias.
      String(id.split(separator: "-").first!.reversed())
    }
  }

  public struct State: Codable, Sendable {
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
  let priceField = SQLite.Expression<Double?>("price")

  let lock: NSLock = NSLock()

  let connection: Connection
  let batchSize: Int
  let imageSize: Int
  public var state: State

  public init(dbPath: String, batchSize: Int, imageSize: Int = 224) throws {
    connection = try Connection(dbPath)
    self.batchSize = batchSize
    self.imageSize = imageSize
    self.state = State(images: [], offset: 0)

    print(" [DataIterator] listing products...")
    for item in try connection.prepare(
      productImagesTable.filter(errorField == nil).select([idField])
    ) { state.images.append(.product(item[idField])) }
    print(" [DataIterator] listing LTKs...")
    for item in try connection.prepare(ltkImagesTable.filter(errorField == nil).select([idField])) {
      state.images.append(.ltk(item[idField]))
    }
    print(" [DataIterator] sorting dataset...")
    var keys = [String: String]()
    for img in state.images { keys[img.id] = img.sortKey }
    state.images.sort { x, y in keys[x.id]! < keys[y.id]! }
  }

  public func splitTrainTest() -> (train: DataIterator, test: DataIterator) {
    var train = self
    var test = self
    train.state.images = train.state.images.filter { !$0.id.starts(with: "0") }
    test.state.images = test.state.images.filter { $0.id.starts(with: "0") }
    return (train: train, test: test)
  }

  public mutating func next() -> Swift.Result<(Tensor, [[String: Label]], State), Error>? {
    var batch = [Tensor]()
    var labels = [[String: Label]]()
    for _ in 0..<batchSize {
      do {
        let (img, label) = try nextExample()
        batch.append(img)
        labels.append(label)
      } catch { return .failure(error) }
    }
    return .success((Tensor(stack: batch), labels, state))
  }

  mutating func nextExample() throws -> (Tensor, [String: Label]) {
    while !state.images.isEmpty {
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
    throw DataError.noData
  }

  func read(ltk: String) throws -> (Tensor, [String: Label]) {
    let imageData = try lock.withLock {
      let it = try connection.prepare(ltkImagesTable.filter(idField == ltk))
      return it.makeIterator().next()![dataField]!
    }
    guard let imgTensor = loadImage(imageData, imageSize: imageSize) else {
      throw DataError.decodeImage
    }
    return (
      imgTensor,
      [ImageKind.fieldName: .categorical(count: ImageKind.count, label: ImageKind.product.rawValue)]
    )
  }

  func read(product: String) throws -> (Tensor, [String: Label]) {
    let imageData = try lock.withLock {
      let it = try connection.prepare(productImagesTable.filter(idField == product))
      return it.makeIterator().next()![dataField]!
    }
    guard let imgTensor = loadImage(imageData, imageSize: imageSize) else {
      throw DataError.decodeImage
    }
    var fields: [String: Label] = [
      ImageKind.fieldName: .categorical(count: ImageKind.count, label: ImageKind.ltk.rawValue)
    ]
    let price = try lock.withLock {
      let it = try connection.prepare(productsTable.filter(idField == product))
      return it.makeIterator().next()![priceField]
    }
    if let price = price {
      fields["product_price"] = .categorical(
        count: PriceRange.count,
        label: PriceRange.from(price: price).rawValue
      )
    }
    return (imgTensor, fields)
  }
}
