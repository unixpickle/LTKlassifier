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
    guard case .child(let predictionState) = state["_prediction"] else {
      throw LoadError.missingKey("_prediction")
    }
    guard case .child(let labelsState) = predictionState["_predictors"] else {
      throw LoadError.missingKey("_predictors")
    }
    let stateLabels = Array(labelsState.keys)

    let newShape = backbone.outConv.conv.weight.shape
    let oldShape = weight.shape
    if oldShape != newShape || stateLabels != prediction.labels.keys.map({ $0.rawValue }) {
      let backboneMode = backbone.mode
      let predictionMode = prediction.mode
      backbone = MobileNetV2(inCount: 3, featureCount: oldShape[0])
      prediction = PredictionLayer(
        inputCount: oldShape[0],
        labels: prediction.labels.filter { stateLabels.contains($0.0.rawValue) }
      )
      backbone.mode = backboneMode
      prediction.mode = predictionMode
    }
    try loadState(state)
  }

  public func mergeCompatibleParamsAndGrads() {
    for (field1, field2): (Field, Field) in [
      (.ltkProductKeywords, .productKeywords), (.productRetailer, .ltkRetailers),
    ] {
      if let pred1 = prediction.predictors.children[field1.rawValue],
        let pred2 = prediction.predictors.children[field2.rawValue]
      {
        let params1 = pred1.parameters
        let params2 = pred2.parameters
        for ((_, var param1), (_, var param2)) in zip(params1, params2) {
          if let g1 = param1.grad, let g2 = param2.grad {
            param1.grad = g1 + g2
            param2.grad = nil
          }
          param2.data = param1.data
        }
      }
    }
  }

}
