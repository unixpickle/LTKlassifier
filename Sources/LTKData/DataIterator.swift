import Foundation
import Honeycrisp
import ImageUtils
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
  let nameField = SQLite.Expression<String?>("name")
  let captionField = SQLite.Expression<String>("caption")
  let productIDsField = SQLite.Expression<String>("product_ids")

  let pool: ConnectionPool
  let batchSize: Int
  let imageSize: Int
  public var state: State

  public init(dbPath: String, batchSize: Int, imageSize: Int = 224) throws {
    print(" [DataIterator] connecting DB at \(dbPath) ...")
    pool = ConnectionPool(path: dbPath)
    self.batchSize = batchSize
    self.imageSize = imageSize
    self.state = State(images: [], offset: 0)

    print(" [DataIterator] listing products...")
    try pool.withConnection { connection in
      for item in try connection.prepare(
        productImagesTable.filter(errorField == nil).select([idField])
      ) { state.images.append(.product(item[idField])) }
      print(" [DataIterator] listing LTKs...")
      for item in try connection.prepare(ltkImagesTable.filter(errorField == nil).select([idField]))
      { state.images.append(.ltk(item[idField])) }
      print(" [DataIterator] sorting dataset...")
      var keys = [String: String]()
      for img in state.images { keys[img.id] = img.sortKey }
      state.images.sort { x, y in keys[x.id]! < keys[y.id]! }
    }
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
    while ids.count < batchSize { if let id = popID() { ids.append(id) } else { return nil } }

    let results: SendableArray<(Tensor, [Field: Label])> = SendableArray(count: ids.count)
    while !results.collect().allSatisfy({ $0 != nil }) {
      readIDs(ids, into: results)
      for (i, x) in results.collect().enumerated() {
        if x != nil { continue }
        if let id = popID() { ids[i] = id } else { return nil }
      }
    }
    let allImages = results.collect().map { $0!.0 }
    let allLabels = results.collect().map { $0!.1 }
    return .success((Tensor(stack: allImages), allLabels, state))
  }

  private mutating func popID() -> ImageID? {
    if state.images.isEmpty { return nil }
    let result = state.images[state.offset % state.images.count]
    state.offset = (state.offset + 1) % state.images.count
    return result
  }

  private func readIDs(_ ids: [ImageID], into: SendableArray<(Tensor, [Field: Label])>) {
    let pool = pool
    let imageSize = imageSize
    DispatchQueue.global(qos: .userInitiated).sync {
      DispatchQueue.concurrentPerform(iterations: ids.count) { i in
        if into[i] != nil { return }
        let id = ids[i]
        let reader = DataReader(pool: pool)
        do {
          let (data, fields) = try reader.readExample(id)
          if let img = loadImage(data, imageSize: imageSize) {
            into[i] = (img, fields)
          } else {
            print("image \(id) could not be decoded")
          }
        } catch { print("example \(id) could not be read from the database") }
      }
    }
  }
}

private struct DataReader {
  let pool: ConnectionPool

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
  let nameField = SQLite.Expression<String?>("name")
  let captionField = SQLite.Expression<String>("caption")
  let productIDsField = SQLite.Expression<String>("product_ids")

  public func readExample(_ obj: DataIterator.ImageID) throws -> (Data, [Field: Label]) {
    let (imageData, fields) =
      switch obj {
      case .ltk(let id): try read(ltk: id)
      case .product(let id): try read(product: id)
      }
    return (imageData, fields)
  }

  func read(ltk: String) throws -> (Data, [Field: Label]) {
    try pool.withConnection { connection in
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
        guard let row = try getProductRow(connection, id) else { continue }
        productCount += 1
        if let price = try productDollarAmount(connection, row) {
          totalDollars += price
        } else {
          allProductsHavePrice = false
        }
        if let retailer = row[retailerDisplayNameField] {
          retailers[Retailer.label(retailer)] = true
        }
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
  }

  func read(product: String) throws -> (Data, [Field: Label]) {
    try pool.withConnection { connection in
      let imageData = try connection.prepare(productImagesTable.filter(idField == product))
        .makeIterator().next()![dataField]!

      var fields: [Field: Label] = [
        .imageKind: .categorical(count: ImageKind.count, label: ImageKind.product.rawValue)
      ]

      if let record = try getProductRow(connection, product) {
        if let price = try productDollarAmount(connection, record) {
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
        if let name = record[nameField],
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          var keywords = [Bool](repeating: false, count: ProductKeyword.count)
          for token in name.lowercased().components(separatedBy: .whitespacesAndNewlines) {
            if let tokenIdx = ProductKeyword.label(token) { keywords[tokenIdx] = true }
          }
          fields[.productKeywords] = .bitset(keywords)
        }
      }

      return (imageData, fields)
    }
  }

  func getProductRow(_ connection: Connection, _ id: String) throws -> Row? {
    return try connection.prepare(productsTable.filter(idField == id)).makeIterator().next()
  }

  func productDollarAmount(_ connection: Connection, _ row: Row) throws -> Double? {
    guard let price = row[priceField], let currencyName = row[currencyField],
      let currency = Currency.parse(currencyName)
    else { return nil }
    return currency.intoDollars(price)
  }
}
