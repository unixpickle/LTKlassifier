import HCBacktrace
import Honeycrisp
import LTKLabel

public class Model: Trainable {

  @Child var backbone: MobileNetV2
  @Child var prediction: PredictionLayer

  public init(labels: [Field: LabelDescriptor]) {
    super.init()
    self.backbone = MobileNetV2(inCount: 3)
    self.prediction = PredictionLayer(inputCount: 1280, labels: labels)
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> [Field: Tensor] {
    return prediction(backbone(x))
  }

}
