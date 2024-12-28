import HCBacktrace
import Honeycrisp

public enum LabelDescriptor {
  case categorical(Int)
  case bitset(Int)

  public var channelCount: Int {
    switch self {
    case .categorical(let count): count
    case .bitset(let count): count
    }
  }
}

public enum Label {
  case categorical(count: Int, label: Int)
  case bitset([Bool])

  public var descriptor: LabelDescriptor {
    switch self {
    case .categorical(let count, _): .categorical(count)
    case .bitset(let bits): .bitset(bits.count)
    }
  }
}

public class LabelPredictor: Trainable {

  public let descriptor: LabelDescriptor
  @Child var layer: Linear

  public init(inputCount: Int, descriptor: LabelDescriptor) {
    self.descriptor = descriptor
    super.init()
    layer = Linear(inCount: inputCount, outCount: descriptor.channelCount)
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> Tensor { layer(x) }

}

public class PredictionLayer: Trainable {

  public let inputCount: Int
  public let labels: [String: LabelDescriptor]
  @Child var predictors: TrainableDictionary<LabelPredictor>

  public init(inputCount: Int, labels: [String: LabelDescriptor]) {
    self.inputCount = inputCount
    self.labels = labels
    super.init()
    predictors = TrainableDictionary(
      labels.mapValues { desc in LabelPredictor(inputCount: inputCount, descriptor: desc) }
    )
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> [String: Tensor] {
    predictors.children.mapValues { layer in layer(x) }
  }

}
