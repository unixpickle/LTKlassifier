import Foundation
import HCBacktrace
import Honeycrisp

class GradClipper {
  struct State: Codable { let history: [Float] }

  let historySize: Int
  let recentCount: Int
  let maxStds: Float
  private var history: [Float] = []

  init(historySize: Int = 30, recentCount: Int = 5, maxStds: Float = 2.0) {
    self.historySize = historySize
    self.recentCount = recentCount
    self.maxStds = maxStds
  }

  public var state: State {
    get { State(history: history) }
    set { history = newValue.history }
  }

  @recordCaller private func _clipGrads(model: Trainable) async throws -> (Float, Float) {
    var gradNorm = Tensor(data: [0.0])
    for (_, p) in model.parameters { if let g = p.grad { gradNorm = gradNorm + g.pow(2).sum() } }
    let actualNorm = try await gradNorm.sqrt().item()

    let (flag, scale) = shouldClip(norm: actualNorm)
    history.append(actualNorm)
    if history.count > historySize + recentCount { history.remove(at: 0) }
    if flag { for (_, var p) in model.parameters { if let g = p.grad { p.grad = g * scale } } }
    return (actualNorm, scale)
  }

  private func shouldClip(norm: Float) -> (Bool, Float) {
    if history.count < historySize + recentCount { return (false, 1.0) }
    let mean = history[..<historySize].reduce(0.0, +) / Float(historySize)
    let std = sqrt(
      history.map { pow($0 - mean, 2) }.reduce(0.0, +) / Float(historySize)
    )
    let threshold = mean + std * maxStds
    return (norm > threshold, min(1, threshold / norm))
  }
}
