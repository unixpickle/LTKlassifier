import ArgumentParser
import Foundation
import HCBacktrace
import Honeycrisp
import LTKData
import LTKLabel
import LTKModel
import ImageUtils

@main struct FilterTrain: AsyncParsableCommand {

  struct State: Codable { var model: Trainable.State }

  struct FeatureShard: Codable {
    var ids: [String]
    var features: TensorState
  }

  @Option(name: .shortAndLong, help: "Path to database.") var dbPath: String
  @Option(name: .shortAndLong, help: "Path to load the model from.") var modelPath: String =
    "model_state.plist"
  @Option(name: .shortAndLong, help: "Directory to save shards into.") var outputDir: String =
    "features"
  @Option(name: .shortAndLong, help: "The batch size for model inference.") var batchSize: Int = 32

  mutating func run() async {
    do {
      Backend.defaultBackend = try MPSBackend(allocator: .bucket)

      print("creating model...")
      let model = Model(labels: LabelDescriptor.allLabels)

      print("loading from checkpoint: \(modelPath) ...")
      let data = try Data(contentsOf: URL(fileURLWithPath: modelPath))
      let decoder = PropertyListDecoder()
      let loadedState = try decoder.decode(State.self, from: data)
      try model.reconfigureAndLoad(loadedState.model)

      let fm = FileManager.default
      if !fm.fileExists(atPath: outputDir) {
        print("creating output directory: \(outputDir)")
        try fm.createDirectory(at: URL(filePath: outputDir), withIntermediateDirectories: false)
      }

      print("listing products...")
      let db = DB(pool: ConnectionPool(path: dbPath))
      let products = try db.listProductsWithImages()

      print("working on shards...")
      let productShards = splitIntoShards(ids: products)
      let outputRoot = URL(filePath: outputDir)
      for (shardIdx, shardIDs) in productShards.enumerated() {
        print("shard \(shardIdx) has \(shardIDs.count) products")
        let shardURL = outputRoot.appending(component: "\(shardIdx).plist")
        var shard =
          if fm.fileExists(atPath: shardURL.path) {
            try {
              let data = try Data(contentsOf: shardURL)
              let decoder = PropertyListDecoder()
              return try decoder.decode(FeatureShard.self, from: data)
            }()
          } else {
            FeatureShard(
              ids: [],
              features: try await Tensor(zeros: [0, model.featureCount]).state()
            )
          }
        let existingFeatures = Tensor(state: shard.features)
        print(" - \(existingFeatures.shape[0]) existing features")
        let existingIDs = Set(shard.ids)
        let newIDs = shardIDs.filter { !existingIDs.contains($0) }

        var completedFeatures = [Tensor]()
        var completedIDs = [String]()

        var batchImageData = [Data]()
        var batchIDs = [String]()
        func flushBatch() async throws {
          if batchIDs.isEmpty { return }

          // Image loading is CPU bound
          let results: SendableArray<Tensor> = .init(count: batchIDs.count)
          let inputData = batchImageData
          DispatchQueue.global(qos: .userInitiated).sync {
            DispatchQueue.concurrentPerform(iterations: inputData.count) { i in
              if let img = loadImage(inputData[i], imageSize: 224) { results[i] = img }
            }
          }

          var inputs = [Tensor]()
          for (id, tensor) in zip(batchIDs, results.collect()) {
            guard let tensor = tensor else { continue }
            inputs.append(tensor)
            completedIDs.append(id)
          }

          let inputTensor = Tensor(stack: inputs)
          let outputs = Tensor.withGrad(enabled: false) { model.backbone(inputTensor) }
          try await outputs.wait()
          completedFeatures.append(outputs)

          batchIDs = []
          batchImageData = []
        }

        for id in newIDs {
          if let data = try db.getProductImage(id: id) {
            batchImageData.append(data)
            batchIDs.append(id)
            if batchImageData.count == batchSize { try await flushBatch() }
          }
        }
        try await flushBatch()

        shard.features = try await CPUBackend.global.use {
          try await Tensor(concat: [existingFeatures] + completedFeatures).state()
        }
        shard.ids = shard.ids + completedIDs
        print(" - processed \(completedIDs.count)/\(newIDs.count) images")
        let data = try PropertyListEncoder().encode(shard)
        try data.write(to: shardURL, options: .atomic)
        print(" - wrote shard with a total of \(shard.ids.count) features")
      }
    } catch { print("fatal error: \(error)") }
  }

  private func splitIntoShards(ids: [String]) -> [[String]] {
    var shards = [[String]](repeating: [], count: 256)
    for id in ids {
      let prefix = String(id.split(separator: "-").first!.reversed()[0..<2])
      let targetIdx = Int(prefix, radix: 16)!
      shards[targetIdx].append(id)
    }
    return shards
  }
}
