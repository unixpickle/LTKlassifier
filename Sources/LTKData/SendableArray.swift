import Foundation

final class SendableArray<T: Sendable>: Sendable {
  let lock = NSLock()
  nonisolated(unsafe) var data: [T?]

  public init(count: Int) { data = [T?](repeating: nil, count: count) }

  public subscript(index: Int) -> T? {
    get { lock.withLock { data[index] } }
    set { lock.withLock { data[index] = newValue } }
  }

  public func collect() -> [T] { lock.withLock { data.map { $0! } } }
}
