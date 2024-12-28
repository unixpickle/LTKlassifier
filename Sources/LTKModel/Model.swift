import HCBacktrace
import Honeycrisp

public class Model: Trainable {

  @Child var prediction: PredictionLayer

  public init(labels: [String: LabelDescriptor]) {
    super.init()
    self.prediction = PredictionLayer(inputCount: 1000, labels: labels)
  }

}
