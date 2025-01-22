import Foundation
import SQLite

/// Maintain a separate SQLite3 connection per thread.
final class ConnectionPool: Sendable {
  private static let threadKey: String = "ConnectionPoolThreadKey"

  let path: String

  public init(path: String) { self.path = path }

  public func withConnection<T>(_ fn: (Connection) throws -> T) throws -> T {
    if let value = Thread.current.threadDictionary[ConnectionPool.threadKey],
      let conn = value as? Connection
    {
      return try fn(conn)
    }
    let conn = try Connection(path)
    Thread.current.threadDictionary[ConnectionPool.threadKey] = conn
    return try fn(conn)
  }
}
