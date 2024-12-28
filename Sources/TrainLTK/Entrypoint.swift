import ArgumentParser
import Honeycrisp

@main struct FilterTrain: AsyncParsableCommand {

  struct State: Codable {
    var model: Trainable.State
    var opt: Adam.State?
    var step: Int?
  }

  @Option(name: .shortAndLong, help: "Output path for the save state.") var outputPath: String =
    "model_state.plist"
  @Option(name: .shortAndLong, help: "The learning rate for training.") var learningRate: Float =
    0.001
  @Option(name: .shortAndLong, help: "The weight decay for training.") var weightDecay: Float = 0.01
  @Option(name: .shortAndLong, help: "The batch size for training.") var batchSize: Int = 8
  @Option(name: .shortAndLong, help: "Steps between model saves.") var saveInterval: Int = 1000

  mutating func run() async {
    do {
      let flopCounter = BackendFLOPCounter(wrapping: try MPSBackend(allocator: .bucket))
      Backend.defaultBackend = flopCounter  // TODO: this.
    } catch { print("fatal error: \(error)") }
  }
}
