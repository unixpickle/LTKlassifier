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
