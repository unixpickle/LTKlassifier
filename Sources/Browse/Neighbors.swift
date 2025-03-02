import Foundation
import Honeycrisp

public final class Neighbors: Sendable {

  public enum NeighborError: Error { case idNotFound(String) }

  struct FeatureShard: Codable {
    var ids: [String]
    var features: TensorState
  }

  private let ids: [String]
  private let features: Tensor
  public let clusterStart: [String]

  public init(featureDir: String, clusterPath: String) async throws {
    let decoder = PropertyListDecoder()

    var allFeatures: Tensor? = nil
    var allIDs = [String]()
    for shardIdx in 0..<100 {
      let shardURL = URL(filePath: featureDir).appending(component: "\(shardIdx).plist")
      let data = try Data(contentsOf: shardURL)
      let shard = try decoder.decode(FeatureShard.self, from: data)
      let shardFeatures = Tensor(state: shard.features)
      allFeatures =
        if let f = allFeatures { Tensor(concat: [f, shardFeatures]) } else { shardFeatures }
      allIDs.append(contentsOf: shard.ids)
    }
    ids = allIDs
    features = allFeatures! / allFeatures!.pow(2).sum(axis: 1, keepdims: true).sqrt()

    if FileManager.default.fileExists(atPath: clusterPath) {
      let data = try Data(contentsOf: URL(filePath: clusterPath))
      clusterStart = try decoder.decode([String].self, from: data)
    } else {
      print("clustering features...")
      var totalCenters = [Int]()
      for centerCount in [16, 32, 64] {
        print("clustering for center count \(centerCount) ...")
        for i in try await Neighbors.cluster(data: features, centerCount: centerCount) {
          if !totalCenters.contains(i) { totalCenters.append(i) }
        }
      }
      clusterStart = totalCenters.map { [ids] in ids[$0] }
      let data = try PropertyListEncoder().encode(clusterStart)
      try data.write(to: URL(filePath: clusterPath), options: .atomic)
    }
  }

  public func neighbors(id: String, strides: [Int], limit: Int = 64) async throws -> [Int: [String]]
  {
    guard let sourceIdx = ids.firstIndex(of: id) else { throw NeighborError.idNotFound(id) }
    let sourceFeature = features[sourceIdx]
    let distances = pairwiseDistances(features, sourceFeature.unsqueeze(axis: 0)).squeeze(axis: 1)
    let idxs = distances.argsort(axis: 0)[1...]
    var results = [Int: [String]]()
    for s in strides {
      let stridedIdxs = stride(from: s - 1, to: min(idxs.shape[0], (limit + 1) * s), by: s)
      results[s] = try await idxs[stridedIdxs].ints().map { ids[$0] }
    }
    return results
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
    }

    return try await pairwiseDistances(data, centers).argmin(axis: 0).ints()
  }

}

func pairwiseDistances(_ data: Tensor, _ queries: Tensor) -> Tensor {
  data.pow(2).sum(axis: 1).unsqueeze(axis: 1) + queries.pow(2).sum(axis: 1).unsqueeze(axis: 0) - 2
    * (data &* queries.t())
}
