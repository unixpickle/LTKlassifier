import HCBacktrace
import Honeycrisp
import LTKLabel
import LTKModel

struct ModelWrapper: Sendable {

  public struct Classification: Codable {
    public let productProb: Float
    public let keywordProbs: [String: Float]
  }

  let model: SyncTrainable<Model>

  var featureCount: Int { model.use { $0.featureCount } }

  func classify(feature: Tensor) async throws -> Classification {
    let labels = model.use { $0.prediction(feature.unsqueeze(axis: 0)) }
    let prodProb: Float = try await labels[.imageKind]!.flatten().softmax(axis: 0).floats()[
      ImageKind.product.rawValue
    ]
    let keywordProbs = try await labels[.productKeywords]!.flatten().softmax(axis: 0).floats()
    let keywordMap = Dictionary(
      uniqueKeysWithValues: zip(Field.productKeywords.valueNames(), keywordProbs)
    )
    return Classification(productProb: prodProb, keywordProbs: keywordMap)
  }

  func feature(keyword: String) throws -> Tensor {
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

  @recordCaller private func _encodeImage(_ image: Tensor) -> Tensor {
    model.use { $0.backbone(image.unsqueeze(axis: 0)).flatten() }
  }

}
