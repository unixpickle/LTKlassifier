import HCBacktrace
import Honeycrisp
import LTKLabel

public class Model: Trainable {

  @Child public var backbone: MobileNetV2
  @Child public var prediction: PredictionLayer

  public var featureCount: Int { backbone.outConv.conv.weight.shape[0] }

  public init(labels: [Field: LabelDescriptor], featureCount: Int = 1280) {
    super.init()
    self.backbone = MobileNetV2(inCount: 3, featureCount: featureCount)
    self.prediction = PredictionLayer(inputCount: featureCount, labels: labels)
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> [Field: Tensor] {
    return prediction(backbone(x))
  }

  public enum LoadError: Error { case missingKey(String) }

  @recordCaller private func _reconfigureAndLoad(_ state: State) throws {
    guard case .child(let backboneState) = state["_backbone"] else {
      throw LoadError.missingKey("_backbone")
    }
    guard case .child(let outConvState) = backboneState["_outConv"] else {
      throw LoadError.missingKey("_outConv")
    }
    guard case .child(let convState) = outConvState["_conv"] else {
      throw LoadError.missingKey("_conv")
    }
    guard case .tensor(let weight) = convState["weight"] else {
      throw LoadError.missingKey("weight")
    }
    let newShape = backbone.outConv.conv.weight.shape
    let oldShape = weight.shape
    if oldShape != newShape {
      let backboneMode = backbone.mode
      let predictionMode = prediction.mode
      backbone = MobileNetV2(inCount: 3, featureCount: oldShape[0])
      prediction = PredictionLayer(inputCount: oldShape[0], labels: prediction.labels)
      backbone.mode = backboneMode
      prediction.mode = predictionMode
    }
    try loadState(state)
  }

}
