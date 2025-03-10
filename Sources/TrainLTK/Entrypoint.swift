import ArgumentParser
import Foundation
import HCBacktrace
import Honeycrisp
import LTKData
import LTKLabel
import LTKModel

@main struct FilterTrain: AsyncParsableCommand {

  struct State: Codable {
    var step: Int?
    var trainData: DataIterator.State?
    var testData: DataIterator.State?
    var model: Trainable.State
    var opt: Adam.State?
    var clipper: GradClipper.State?
  }

  @Option(name: .shortAndLong, help: "Path to database.") var dbPath: String
  @Option(name: .shortAndLong, help: "Output path for the save state.") var outputPath: String =
    "model_state.plist"
  @Option(name: .shortAndLong, help: "Output layer feature count for the model.") var featureCount:
    Int = 1280
  @Option(name: .shortAndLong, help: "The learning rate for training.") var learningRate: Float =
    0.001
  @Option(name: .shortAndLong, help: "The weight decay for training.") var weightDecay: Float = 0.01
  @Option(name: .shortAndLong, help: "The batch size for training.") var batchSize: Int = 8
  @Option(name: .shortAndLong, help: "Steps between model saves.") var saveInterval: Int = 1000
  @Flag(name: .long, help: "Do not augment image data.") var noAugment: Bool = false
  @Flag(name: .long, help: "Pad raw images to be square before processing.") var padToSquare: Bool =
    false
  @Flag(name: .long, help: "Use model eval mode.") var evalMode: Bool = false
  @Flag(name: .long, help: "Share parameters between LTK and product heads when possible.")
  var shareParameters: Bool = false

  mutating func run() async {
    do {
      let flopCounter = BackendFLOPCounter(wrapping: try MPSBackend(allocator: .bucket))
      Backend.defaultBackend = flopCounter

      var loadedState: State? = nil
      if FileManager.default.fileExists(atPath: outputPath) {
        print("loading from checkpoint: \(outputPath) ...")
        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let decoder = PropertyListDecoder()
        loadedState = try decoder.decode(State.self, from: data)
      }

      print("creating model...")
      let model = Model(labels: LabelDescriptor.allLabels, featureCount: featureCount)
      if let state = loadedState?.model { try model.reconfigureAndLoad(state) }
      if evalMode { model.mode = .inference }

      print("creating data iterator...")
      let dataIt = try {
        var (trainLoader, testLoader) = try DataIterator(
          dbPath: dbPath,
          batchSize: batchSize,
          augment: !noAugment,
          pad: padToSquare
        ).splitTrainTest()
        if let s = loadedState {
          if let ts = s.trainData { trainLoader.state = ts }
          if let ts = s.testData { testLoader.state = ts }
        }
        return loadDataInBackgroundSending(
          zip(trainLoader, testLoader).lazy.map { (x, y) in
            switch x {
            case .success(let x):
              switch y {
              case .success(let y): .success((x, y))
              case .failure(let e): .failure(e)
              }
            case .failure(let e): .failure(e)
            }
          }
        )
      }()

      print("creating optimizer...")
      let opt = Adam(model.parameters, lr: learningRate, weightDecay: weightDecay)
      let clipper = GradClipper()
      if let state = loadedState?.opt { try opt.loadState(state) }
      if let state = loadedState?.clipper { clipper.state = state }
      var step = loadedState?.step ?? 0

      print("training...")
      let startTime = DispatchTime.now()
      var lastItTime = DispatchTime.now()
      for try await ((trainImg, trainLabel, trainState), (testImg, testLabel, testState)) in dataIt
      {
        let dataTime = DispatchTime.now().uptimeNanoseconds - lastItTime.uptimeNanoseconds

        func computeLosses(imgs: Tensor, labels: [[Field: Label]]) -> ([Field: Tensor], Tensor) {
          let preds = model(imgs)
          let allFields = Set(labels.flatMap { $0.keys })
          var results = [Field: Tensor]()
          var totalLoss = Tensor(zeros: [imgs.shape[0]])
          for field in allFields {
            let indices = labels.enumerated().flatMap { (i, f) in f[field] == nil ? [] : [i] }
            let targets = labels.flatMap { f in f[field] == nil ? [] : [f[field]!] }
            let outputs = preds[field]!.gather(axis: 0, indices: Tensor(data: indices))
            let losses = labelLosses(predictions: outputs, targets: targets)
            results[field] = losses.mean()
            totalLoss = totalLoss + losses.sum() / Float(imgs.shape[0])
          }
          return (results, totalLoss)
        }
        let (trainLosses, loss) = computeLosses(imgs: trainImg, labels: trainLabel)
        let (testLosses, _) = Tensor.withGrad(enabled: false) {
          model.withMode(.inference) { computeLosses(imgs: testImg, labels: testLabel) }
        }

        var logFields = [String]()
        for (prefixKey, losses) in [("test", testLosses), ("train", trainLosses)] {
          for (key, loss) in losses {
            logFields.append("\(prefixKey)_\(key.rawValue)=\(try await loss.item())")
          }
        }

        loss.backward()
        if shareParameters { model.mergeCompatibleParamsAndGrads() }

        let (gradNorm, clipScale) = try await clipper.clipGrads(model: model)
        if !gradNorm.isFinite {
          print("NaN detected in gradient!")
          for (name, param) in model.parameters {
            if let g = param.grad { print(name, try await g.pow(2).sum().sqrt().item()) }
          }
          fatalError()
        }

        opt.step()
        opt.clearGrads()
        if shareParameters { model.mergeCompatibleParamsAndGrads() }
        step += 1

        logFields.append("grad_norm=\(gradNorm)")
        logFields.append("grad_scale=\(clipScale)")
        let gflops =
          Double(flopCounter.flopCount)
          / Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds)
        logFields.append("gflops=\(gflops)")
        logFields.append("data_secs=\(Double(dataTime) / 1e9)")
        logFields.sort()
        print("step \(step): \(logFields.joined(separator: " "))")

        if step % saveInterval == 0 {
          print("saving to: \(outputPath) ...")
          let state = State(
            step: step,
            trainData: trainState,
            testData: testState,
            model: try await model.state(),
            opt: try await opt.state()
          )
          let stateData = try PropertyListEncoder().encode(state)
          try stateData.write(to: URL(filePath: outputPath), options: .atomic)
        }

        lastItTime = DispatchTime.now()
      }
    } catch { print("fatal error: \(error)") }
  }

  func gradNorm(_ model: Trainable) async throws -> Float {
    var sum = Tensor(zeros: [])
    for (_, param) in model.parameters { if let g = param.grad { sum = sum + g.pow(2).sum() } }
    return try await sum.sqrt().item()
  }
}

public func labelLosses(predictions: Tensor, targets: [Label]) -> Tensor {
  switch targets[0] {
  case .bitset(let x):
    #alwaysAssert(x.count == predictions.shape[1])
    var allBits = [Bool]()
    for target in targets {
      guard case .bitset(let bits) = target else { fatalError("mismatched type") }
      allBits.append(contentsOf: bits)
    }
    let targetTensor = Tensor(data: allBits, shape: predictions.shape, dtype: .bool)
    return -targetTensor.when(isTrue: logSigmoid(predictions), isFalse: logSigmoid(-predictions))
      .sum(axis: -1)
  case .categorical(let count, _):
    #alwaysAssert(count == predictions.shape[1])
    var allTargets = [Int]()
    for target in targets {
      guard case .categorical(_, let category) = target else { fatalError("mismatched type") }
      allTargets.append(category)
    }
    let targetTensor = Tensor(data: allTargets, shape: [targets.count, 1], dtype: .int64)
    return -predictions.logSoftmax(axis: -1).gather(axis: -1, indices: targetTensor).squeeze(
      axis: -1
    )
  }
}

func logSigmoid(_ x: Tensor) -> Tensor {
  return (x <= -10).when(isTrue: x, isFalse: x.clamp(min: -10.0).sigmoid().log())
}
