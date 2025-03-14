@MainActor public final class RateLimiter: Sendable {
  public struct RateLimitExceeded: Error {}

  private let maximum: Double
  private let leakPerMinute: Double
  private var usage: [String: Double]
  private var task: Task<(), Never>? = nil

  public init(maxPerHour: Double) {
    leakPerMinute = maxPerHour / 60.0
    maximum = maxPerHour
    usage = [:]

    task = Task { [weak self] () -> Void in
      while true {
        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
        guard let self = self else { return }
        for (host, usageForName) in self.usage {
          let newUsage = usageForName - self.leakPerMinute
          if newUsage < 0 {
            self.usage.removeValue(forKey: host)
          } else {
            self.usage[host] = newUsage
          }
        }
      }
    }
  }

  @MainActor func use(host: String) -> Bool {
    if usage[host] ?? 0.0 >= maximum { return false }
    usage[host] = (usage[host] ?? 0.0) + 1.0
    return true
  }

  deinit { if let task = task { task.cancel() } }
}

public struct TooManyConcurrentRequests: Error {}

@MainActor public final class KeyedSemaphore<K: Hashable>: Sendable where K: Sendable {
  @MainActor private class Waiter {
    var continuation: CheckedContinuation<Void, Never>? = nil
    var accepted: Bool = false
  }

  public let limit: Int
  public let queueLimit: Int
  private var usageCount = [K: Int]()
  private var waiters = [K: [Waiter]]()

  public init(limit: Int, queueLimit: Int = 1000) {
    self.limit = limit
    self.queueLimit = queueLimit
  }

  public func use<T: Sendable>(key: K, fn: () async throws -> T) async throws -> T {
    let count = (usageCount[key] ?? 0)
    if count < limit { usageCount[key] = count + 1 } else { try await waitFor(key: key) }
    defer { wakeUp(key: key) }
    return try await fn()
  }

  private func waitFor(key: K) async throws {
    let waiter = Waiter()
    try add(waiter: waiter, key: key)
    await withCheckedContinuation { @MainActor continuation -> Void in
      if waiter.accepted {
        continuation.resume(returning: ())
      } else {
        waiter.continuation = continuation
      }
    }
  }

  private func wakeUp(key: K) {
    if let waiter = unshift(key: key) {
      if let continuation = waiter.continuation {
        continuation.resume(returning: ())
      } else {
        waiter.accepted = true
      }
    } else if let count = usageCount[key] {
      if count == 1 { usageCount.removeValue(forKey: key) } else { usageCount[key] = count - 1 }
    }
  }

  private func add(waiter: Waiter, key: K) throws {
    guard var list = waiters.removeValue(forKey: key) else {
      waiters[key] = [waiter]
      return
    }
    if list.count > queueLimit {
      waiters[key] = list
      throw TooManyConcurrentRequests()
    }
    list.append(waiter)
    waiters[key] = list
  }

  private func unshift(key: K) -> Waiter? {
    guard var list = waiters.removeValue(forKey: key) else { return nil }
    let result = list.remove(at: 0)
    if !list.isEmpty { waiters[key] = list }
    return result
  }

}
