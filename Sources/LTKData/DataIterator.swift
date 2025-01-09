import Foundation
import Honeycrisp
import LTKLabel
import SQLite

public enum DataError: Error {
  case noData
  case decodeImage
}

public enum Currency {
  case usd
  case eur
  case gbp
  case php
  case aud
  case sgd
  case cad
  case nok
  case brl
  case chf
  case clp
  case mxn
  case vnd
  case hkd
  case sek
  case uah
  case ils
  case tryy
  case aed

  static func parse(_ x: String) -> Self? {
    switch x {
    case "USD": .usd
    case "EUR": .eur
    case "GBP": .gbp
    case "PHP": .php
    case "AUD": .aud
    case "SGD": .sgd
    case "CAD": .cad
    case "NOK": .nok
    case "BRL": .brl
    case "CHF": .chf
    case "CLP": .clp
    case "MXN": .mxn
    case "VND": .vnd
    case "HKD": .hkd
    case "SEK": .sek
    case "UAH": .uah
    case "ILS": .ils
    case "TRY": .tryy
    case "AED": .aed
    default: nil
    }
  }

  func intoDollars(_ x: Double) -> Double {
    switch self {
    case .usd: x
    case .eur: x / 0.9589
    case .gbp: x / 0.7951
    case .php: x / 57.899
    case .aud: x / 1.6068
    case .sgd: x / 1.3581
    case .cad: x / 1.4405
    case .nok: x / 11.0019
    case .brl: x / 5.0
    case .chf: x / 0.9017
    case .clp: x / 900.0
    case .mxn: x / 20.333
    case .vnd: x / 23000.0
    case .hkd: x / 7.7656
    case .sek: x / 10.5
    case .uah: x / 27.0
    case .ils: x / 3.5
    case .tryy: x / 25.0
    case .aed: x / 3.6725
    }
  }
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
    let imageData = try connection.prepare(ltkImagesTable.filter(idField == ltk)).makeIterator()
      .next()![dataField]!
    guard let imgTensor = loadImage(imageData, imageSize: imageSize) else {
      throw DataError.decodeImage
    }
    var fields: [String: Label] = [
      ImageKind.fieldName: .categorical(count: ImageKind.count, label: ImageKind.ltk.rawValue)
    ]
    let productIDs = try connection.prepare(ltksTable.filter(idField == ltk)).makeIterator()
      .next()![productIDsField]
    var totalDollars: Double = 0.0
    var hasTotalPrice: Bool = true
    var productCount: Int = 0
    for id in productIDs.split(separator: ",") {
      if id.isEmpty { continue }
      productCount += 1
      if let price = try productDollarAmount(String(id)) {
        totalDollars += price
      } else {
        hasTotalPrice = false
      }
    }
    if hasTotalPrice && productCount > 0 {
      fields["ltk_total_dollars"] = .categorical(
        count: PriceRange.count,
        label: PriceRange.from(price: totalDollars).rawValue
      )
    }
    fields["ltk_product_count"] = .categorical(count: 16, label: Swift.max(productCount, 15))
    return (imgTensor, fields)
  }

  func read(product: String) throws -> (Tensor, [String: Label]) {
    guard
      let firstRow = try connection.prepare(productImagesTable.filter(idField == product))
        .makeIterator().next()
    else { fatalError("no row") }
    let imageData = firstRow[dataField]!
    guard let imgTensor = loadImage(imageData, imageSize: imageSize) else {
      throw DataError.decodeImage
    }
    var fields: [String: Label] = [
      ImageKind.fieldName: .categorical(count: ImageKind.count, label: ImageKind.product.rawValue)
    ]
    if let price = try productDollarAmount(product) {
      fields["product_dollars"] = .categorical(
        count: PriceRange.count,
        label: PriceRange.from(price: price).rawValue
      )
    }
    return (imgTensor, fields)
  }

  func productDollarAmount(_ id: String) throws -> Double? {
    let it = try connection.prepare(productsTable.filter(idField == id))
    guard let item = it.makeIterator().next() else { return nil }
    guard let price = item[priceField], let currencyName = item[currencyField],
      let currency = Currency.parse(currencyName)
    else { return nil }
    return currency.intoDollars(price)
  }
}
