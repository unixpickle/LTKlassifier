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

  public init(featureDir: String, clusterPath: String, duplicatesPath: String) async throws {
    let decoder = PropertyListDecoder()

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
    print("created initial feature matrix")

    let duplicateIDs =
      if FileManager.default.fileExists(atPath: clusterPath) {
        try {
          let data = try Data(contentsOf: URL(filePath: duplicatesPath))
          return try decoder.decode([String].self, from: data)
        }()
      } else {
        try await {
          print("deduplicating data...")
          let dupIndices = try await Self.duplicates(data: features)
          print(" - deleting \(dupIndices.count)/\(ids.count)")
          let dupIDs = dupIndices.map { ids[$0] }
          let data = try PropertyListEncoder().encode(dupIDs)
          try data.write(to: URL(filePath: duplicatesPath), options: .atomic)
          return dupIDs
        }()
      }
    let dupSet = Set(duplicateIDs)
    let dedupIDs = ids.enumerated().filter { !dupSet.contains($0.1) }.map { $0.0 }
    features = features.gather(axis: 0, indices: Tensor(data: dedupIDs))
    ids = dedupIDs.map { ids[$0] }

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
    self.features = features
    self.ids = ids
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

  public static func duplicates(data: Tensor, threshold: Float = 0.2) async throws -> [Int] {
    let bs = 128
    var results = [Int]()
    for i in stride(from: 0, to: data.shape[0], by: bs) {
      print("scanned \(i)/\(data.shape[0]) images with \(results.count) duplicates")
      let minBatch = min(bs, data.shape[0] - i)
      let localBatch = data[i..<(i + minBatch)]
      let distances = pairwiseDistances(data, localBatch)
      let mask =
        Tensor(data: 0..<data.shape[0]).unsqueeze(axis: 1) < Tensor(data: i..<(i + minBatch))
      let dupes = try await ((distances < threshold) & mask).some(axis: 1).bools()
      results.append(contentsOf: zip(i..<(i + minBatch), dupes).filter { $0.1 }.map { $0.0 })
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
      try await centers.wait()
    }

    return try await pairwiseDistances(data, centers).argmin(axis: 0).ints()
  }

}

func pairwiseDistances(_ data: Tensor, _ queries: Tensor) -> Tensor {
  data.pow(2).sum(axis: 1).unsqueeze(axis: 1) + queries.pow(2).sum(axis: 1).unsqueeze(axis: 0) - 2
    * (data &* queries.t())
}
