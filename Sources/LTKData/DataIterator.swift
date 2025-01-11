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
  let currencyField = SQLite.Expression<String?>("currency")
  let retailerDisplayNameField = SQLite.Expression<String?>("retailer_display_name")
  let captionField = SQLite.Expression<String>("caption")
  let productIDsField = SQLite.Expression<String>("product_ids")

  let connection: Connection
  let batchSize: Int
  let imageSize: Int
  public var state: State

  public init(dbPath: String, batchSize: Int, imageSize: Int = 224) throws {
    print(" [DataIterator] connecting DB at \(dbPath) ...")
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
    train.state.images = train.state.images.filter { !$0.sortKey.starts(with: "0") }
    test.state.images = test.state.images.filter { $0.sortKey.starts(with: "0") }
    return (train: train, test: test)
  }

  public mutating func next() -> Swift.Result<(Tensor, [[Field: Label]], State), Error>? {
    var ids = [ImageID]()
    var datas = [Data]()
    var labels = [[Field: Label]]()
    for _ in 0..<batchSize {
      do {
        let (id, img, label) = try nextExample()
        ids.append(id)
        datas.append(img)
        labels.append(label)
      } catch { return .failure(error) }
    }

    let sendableIDs = ids
    let sendableDatas = datas
    let imageSize = self.imageSize
    let images: SendableArray<Tensor> = SendableArray(count: datas.count)
    DispatchQueue.concurrentPerform(iterations: datas.count) { i in
      let id = sendableIDs[i]
      let data = sendableDatas[i]
      guard let img = loadImage(data, imageSize: imageSize) else {
        fatalError("failed to decode image for \(id)")
      }
      images[i] = img
    }
    return .success((Tensor(stack: images.collect()), labels, state))
  }

  mutating func nextExample() throws -> (ImageID, Data, [Field: Label]) {
    while !state.images.isEmpty {
      let obj = state.images[state.offset % state.images.count]
      do {
        let (imageData, fields) =
          switch obj {
          case .ltk(let id): try read(ltk: id)
          case .product(let id): try read(product: id)
          }
        state.offset += 1
        return (obj, imageData, fields)
      } catch { state.images.remove(at: state.offset % state.images.count) }
    }
    throw DataError.noData
  }

  func read(ltk: String) throws -> (Data, [Field: Label]) {
    let imageData = try connection.prepare(ltkImagesTable.filter(idField == ltk)).makeIterator()
      .next()![dataField]!
    var fields: [Field: Label] = [
      .imageKind: .categorical(count: ImageKind.count, label: ImageKind.ltk.rawValue)
    ]
    let ltkItem = try connection.prepare(ltksTable.filter(idField == ltk)).makeIterator().next()!

    let caption = ltkItem[captionField]
    var hashtags = [Bool](repeating: false, count: Hashtag.count)
    for token in caption.lowercased().components(separatedBy: .whitespacesAndNewlines) {
      if let tokenIdx = Hashtag.label(token) { hashtags[tokenIdx] = true }
    }
    fields[.ltkHashtags] = .bitset(hashtags)

    let productIDs = ltkItem[productIDsField]
    var totalDollars: Double = 0.0
    var allProductsHavePrice: Bool = true
    var productCount: Int = 0
    var retailers = [Bool](repeating: false, count: Retailer.count)
    for id in productIDs.split(separator: ",").map({ String($0) }) {
      if id.isEmpty { continue }
      guard let row = try getProductRow(id) else { continue }
      productCount += 1
      if let price = try productDollarAmount(row) {
        totalDollars += price
      } else {
        allProductsHavePrice = false
      }
      if let retailer = row[retailerDisplayNameField] { retailers[Retailer.label(retailer)] = true }
    }
    if allProductsHavePrice && productCount > 0 {
      fields[.ltkTotalDollars] = .categorical(
        count: PriceRange.count,
        label: PriceRange.from(price: totalDollars).rawValue
      )
    }
    fields[.ltkRetailers] = .bitset(retailers)
    fields[.ltkProductCount] = .categorical(
      count: LabelDescriptor.maxProductCount,
      label: Swift.min(productCount, LabelDescriptor.maxProductCount - 1)
    )

    return (imageData, fields)
  }

  func read(product: String) throws -> (Data, [Field: Label]) {
    let imageData = try connection.prepare(productImagesTable.filter(idField == product))
      .makeIterator().next()![dataField]!

    var fields: [Field: Label] = [
      .imageKind: .categorical(count: ImageKind.count, label: ImageKind.product.rawValue)
    ]

    if let record = try getProductRow(product) {
      if let price = try productDollarAmount(record) {
        fields[.productDollars] = .categorical(
          count: PriceRange.count,
          label: PriceRange.from(price: price).rawValue
        )
      }
      if let retailer = record[retailerDisplayNameField] {
        fields[.productRetailer] = .categorical(
          count: Retailer.count,
          label: Retailer.label(retailer)
        )
      }
    }

    return (imageData, fields)
  }

  func getProductRow(_ id: String) throws -> Row? {
    return try connection.prepare(productsTable.filter(idField == id)).makeIterator().next()
  }

  func productDollarAmount(_ row: Row) throws -> Double? {
    guard let price = row[priceField], let currencyName = row[currencyField],
      let currency = Currency.parse(currencyName)
    else { return nil }
    return currency.intoDollars(price)
  }
}
