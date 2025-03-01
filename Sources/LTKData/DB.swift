import Foundation
import SQLite

public final class DB: Sendable {

  public struct Tables: @unchecked Sendable {
    public let products = Table("products")
    public let productImages = Table("product_images")
    public let ltks = Table("ltks")
    public let ltkImages = Table("ltk_hero_images")
  }

  public struct Fields: @unchecked Sendable {
    public let id = SQLite.Expression<String>("id")
    public let data = SQLite.Expression<Data?>("data")
    public let error = SQLite.Expression<String?>("error")
    public let price = SQLite.Expression<Double?>("price")
    public let currency = SQLite.Expression<String?>("currency")
    public let retailerDisplayName = SQLite.Expression<String?>("retailer_display_name")
    public let name = SQLite.Expression<String?>("name")
    public let caption = SQLite.Expression<String>("caption")
    public let productIDs = SQLite.Expression<String>("product_ids")
    public let hyperlink = SQLite.Expression<String>("hyperlink")
  }

  public let pool: ConnectionPool
  public let tables = Tables()
  public let fields = Fields()

  public init(pool: ConnectionPool) { self.pool = pool }

  public func listProductsWithImages(connection: Connection? = nil) throws -> [String] {
    try withConnection(connection) { connection in
      Array(
        try connection.prepare(tables.productImages.filter(fields.error == nil).select([fields.id]))
          .map { $0[fields.id] }
      )
    }
  }

  public func listLTKsWithImages(connection: Connection? = nil) throws -> [String] {
    try withConnection(connection) { connection in
      Array(
        try connection.prepare(tables.ltkImages.filter(fields.error == nil).select([fields.id])).map
        { $0[fields.id] }
      )
    }
  }

  public func getProduct(id: String, connection: Connection? = nil) throws -> Row? {
    try withConnection(connection) { connection in
      try connection.prepare(tables.products.filter(fields.id == id)).makeIterator().next()
    }
  }

  public func getLTK(id: String, connection: Connection? = nil) throws -> Row? {
    try withConnection(connection) { connection in
      try connection.prepare(tables.ltks.filter(fields.id == id)).makeIterator().next()
    }
  }

  public func getProductImage(id: String, connection: Connection? = nil) throws -> Data? {
    try withConnection(connection) { connection in
      try connection.prepare(tables.productImages.filter(fields.id == id)).makeIterator().next()?[
        fields.data
      ]
    }
  }

  public func getLTKImage(id: String, connection: Connection? = nil) throws -> Data? {
    try withConnection(connection) { connection in
      try connection.prepare(tables.ltkImages.filter(fields.id == id)).makeIterator().next()?[
        fields.data
      ]
    }
  }

  public func productDollarAmount(_ row: Row) throws -> Double? {
    guard let price = row[fields.price], let currencyName = row[fields.currency],
      let currency = Currency.parse(currencyName)
    else { return nil }
    return currency.intoDollars(price)
  }

  private func withConnection<T>(_ connection: Connection? = nil, _ fn: (Connection) throws -> T)
    throws -> T
  { if let c = connection { try fn(c) } else { try pool.withConnection { c in try fn(c) } } }

}
