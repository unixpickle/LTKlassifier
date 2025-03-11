import Foundation
import Honeycrisp
import LTKLabel
import LTKModel

public final class Neighbors: Sendable {

  public enum NeighborError: Error {
    case idNotFound(String)
    case keywordNotFound(String)
  }

  public struct Classification: Codable {
    public let productProb: Float
    public let keywordProbs: [String: Float]
  }

  struct FeatureShard: Codable {
    var ids: [String]
    var features: TensorState
  }

  public let model: SyncTrainable<Model>
  private let ids: [String]
  private let features: Tensor
  public let clusterStart: [String]

  public init(model: sending Model, featureDir: String, clusterPath: String, whitelist: [String]?)
    async throws
  {
    self.model = SyncTrainable(model)

    let decoder = PropertyListDecoder()

    print(" - loading features from \(featureDir) ...")
    var allFeatures: Tensor? = nil
    var allIDs = [String]()
    for shardIdx in 0..<256 {
      let shardURL = URL(filePath: featureDir).appending(component: "\(shardIdx).plist")
      let data = try Data(contentsOf: shardURL)
      let shard = try decoder.decode(FeatureShard.self, from: data)
      let shardFeatures = Tensor(state: shard.features)
      allFeatures =
        if let f = allFeatures { Tensor(concat: [f, shardFeatures]) } else { shardFeatures }
      allIDs.append(contentsOf: shard.ids)
      try await allFeatures!.wait()
    }
    var ids = allIDs
    var features = allFeatures! / allFeatures!.pow(2).sum(axis: 1, keepdims: true).sqrt()
    print(" - created feature matrix with \(ids.count) features")

    if let whitelist = whitelist {
      let allowedIDs = Set(whitelist)
      let useIndices = ids.enumerated().filter { allowedIDs.contains($0.1) }.map { $0.0 }
      ids = useIndices.map { ids[$0] }
      features = features.gather(axis: 0, indices: Tensor(data: useIndices))
      print(" - filtered to \(ids.count) features")
    }

    var clusterStart: [String]
    if FileManager.default.fileExists(atPath: clusterPath) {
      let data = try Data(contentsOf: URL(filePath: clusterPath))
      clusterStart = try decoder.decode([String].self, from: data)
    } else {
      print(" - clustering features...")
      var totalCenters = [Int]()
      for centerCount in [16, 32, 64] {
        print(" - clustering for center count \(centerCount) ...")
        for i in try await Self.cluster(data: features, centerCount: centerCount) {
          if !totalCenters.contains(i) { totalCenters.append(i) }
        }
      }
      clusterStart = totalCenters.map { [ids] in ids[$0] }
      let data = try PropertyListEncoder().encode(clusterStart)
      try data.write(to: URL(filePath: clusterPath), options: .atomic)
    }

    if let whitelist = whitelist {
      let allowedIDs = Set(whitelist)
      clusterStart = clusterStart.filter { allowedIDs.contains($0) }
    }

    self.clusterStart = clusterStart
    self.features = features
    self.ids = ids
  }

  public func neighbors(
    feature: Tensor,
    strides: [Int],
    limit: Int = 128,
    dedupThreshold: Float = 0.02
  ) async throws -> [Int: [String]] {
    let distances = pairwiseDistances(features, feature.unsqueeze(axis: 0)).squeeze(axis: 1)
    let sortedIdxs = distances.argsort(axis: 0)[1...]
    var results = [Int: [String]]()
    for s in strides {
      let idxsInSorted = stride(from: s - 1, to: min(sortedIdxs.shape[0], (limit + 1) * s), by: s)
      let neighborIdxs = sortedIdxs[idxsInSorted]

      // The first feature vector has the highest priority in the dedup, so we
      // make sure we won't show results that are duplicates of the query.
      let useFeatures = Tensor(concat: [
        feature.unsqueeze(axis: 0), features.gather(axis: 0, indices: neighborIdxs),
      ])
      let dedupIndices = try await Self.deduplicate(data: useFeatures, threshold: dedupThreshold)
        .filter { $0 > 0 }.map { $0 - 1 }

      results[s] = try await neighborIdxs.gather(axis: 0, indices: Tensor(data: dedupIndices))
        .ints().map { ids[$0] }
    }
    return results
  }

  public func classify(feature: Tensor) async throws -> Classification {
    let labels = model.use { $0.prediction(feature.unsqueeze(axis: 0)) }
    let prodProb: Float = try await labels[.imageKind]!.flatten().softmax(axis: 0).floats()[
      ImageKind.product.rawValue
    ]
    let keywordProbs = try await labels[.productKeywords]!.flatten().softmax(axis: 0).floats()
    let keywordMap = Dictionary(uniqueKeysWithValues: zip(ProductKeyword.items, keywordProbs))
    return Classification(productProb: prodProb, keywordProbs: keywordMap)
  }

  public func feature(id: String) throws -> Tensor {
    guard let sourceIdx = ids.firstIndex(of: id) else { throw NeighborError.idNotFound(id) }
    return features[sourceIdx]
  }

  public func feature(keyword: String) throws -> Tensor {
    guard let keywordIdx = ProductKeyword.label(keyword) else {
      throw NeighborError.keywordNotFound(keyword)
    }
    var sourceFeature = model.use {
      $0.prediction.predictors.children[Field.productKeywords.rawValue]!.layer.weight.t()[
        keywordIdx
      ]
    }
    sourceFeature = sourceFeature / sourceFeature.pow(2).sum().sqrt()
    return sourceFeature
  }

  /// Return indices of elements in the tensor to keep.
  public static func deduplicate(data: Tensor, threshold: Float, batchSize: Int = 128) async throws
    -> [Int]
  {
    var keepIndices = [Int]()
    for i in stride(from: 0, to: data.shape[0], by: batchSize) {
      let bs = min(batchSize, data.shape[0] - i)
      let localBatch = data[i..<(i + bs)]
      let distances = pairwiseDistances(data, localBatch)
      let mask = Tensor(data: 0..<data.shape[0]).unsqueeze(axis: 1) < Tensor(data: i..<(i + bs))
      let dups = try await ((distances < threshold) & mask).some(axis: 0).bools()
      precondition(dups.count == bs)
      for (j, isDup) in zip(i..<(i + bs), dups) { if !isDup { keepIndices.append(j) } }
    }
    return keepIndices
  }

  /// Cluster the data and return the indices of each center's nearest neighbor.
  private static func cluster(data: Tensor, centerCount: Int, iters: Int = 50) async throws -> [Int]
  {
    var centers = data[stride(from: 0, to: data.shape[0], by: data.shape[0] / centerCount)]

    for _ in 0..<iters {
      let idxs = pairwiseDistances(data, centers).argmin(axis: 1)
      let centerSums = data.scatter(axis: 0, count: centerCount, indices: idxs)
      let centerCounts = Tensor(ones: [data.shape[0]]).scatter(
        axis: 0,
        count: centerCount,
        indices: idxs
      )
      centers = centerSums / centerCounts.unsqueeze(axis: 1)
      try await centers.wait()
    }

    return try await pairwiseDistances(data, centers).argmin(axis: 0).ints()
  }

}

func pairwiseDistances(_ data: Tensor, _ queries: Tensor) -> Tensor {
  data.pow(2).sum(axis: 1).unsqueeze(axis: 1) + queries.pow(2).sum(axis: 1).unsqueeze(axis: 0) - 2
    * (data &* queries.t())
}
