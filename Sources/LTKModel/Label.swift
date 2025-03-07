import HCBacktrace
import Honeycrisp
import LTKLabel

public class LabelPredictor: Trainable {

  public let descriptor: LabelDescriptor
  @Child public var layer: Linear

  public init(inputCount: Int, descriptor: LabelDescriptor) {
    self.descriptor = descriptor
    super.init()
    layer = Linear(inCount: inputCount, outCount: descriptor.channelCount)
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> Tensor { layer(x) }

}

public class PredictionLayer: Trainable {

  public let inputCount: Int
  public let labels: [Field: LabelDescriptor]
  @Child public var predictors: TrainableDictionary<LabelPredictor>

  public init(inputCount: Int, labels: [Field: LabelDescriptor]) {
    self.inputCount = inputCount
    self.labels = labels
    super.init()
    predictors = TrainableDictionary(
      Dictionary(
        uniqueKeysWithValues: labels.map { (k, desc) in
          (k.rawValue, LabelPredictor(inputCount: inputCount, descriptor: desc))
        }
      )
    )
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> [Field: Tensor] {
    let outputs = predictors.children.mapValues { layer in layer(x) }
    return Dictionary(uniqueKeysWithValues: labels.keys.map { k in (k, outputs[k.rawValue]!) })
  }

}
