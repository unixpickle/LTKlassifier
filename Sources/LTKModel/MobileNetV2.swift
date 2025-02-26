import HCBacktrace
import Honeycrisp

public class ConvNormAct: Trainable {
  public let doAct: Bool

  @Child var conv: Conv2D
  @Child var norm: GroupNorm

  public init(
    inCount: Int,
    outCount: Int,
    kernelSize: Int,
    stride: Int = 1,
    depthwise: Bool = false,
    doAct: Bool = true
  ) {
    self.doAct = doAct
    super.init()
    let padding = (kernelSize - 1) / 2
    conv = Conv2D(
      inChannels: inCount,
      outChannels: outCount,
      kernelSize: .square(kernelSize),
      stride: .square(stride),
      padding: .allSides(padding),
      groups: depthwise ? inCount : 1,
      bias: false
    )
    guard let groupCount = [32, 24, 16, 8].first(where: { outCount % $0 == 0 }) else {
      tracedFatalError("cannot create group normalization for channels \(outCount)")
    }
    norm = GroupNorm(groupCount: groupCount, channelCount: outCount)
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> Tensor {
    var h = x
    h = conv(h)
    h = norm(h)
    if doAct { h = h.gelu() }
    return h
  }
}

public class InvertedResidual: Trainable {
  let useResConnect: Bool

  @Child var layers: TrainableArray<ConvNormAct>

  public init(inCount: Int, outCount: Int, stride: Int, expandRatio: Int) {
    useResConnect = (stride == 1 && inCount == outCount)
    super.init()
    let hiddenDim = inCount * expandRatio

    var layers = [ConvNormAct]()
    if expandRatio != 1 {
      layers.append(ConvNormAct(inCount: inCount, outCount: hiddenDim, kernelSize: 1))
    }
    layers.append(
      ConvNormAct(
        inCount: hiddenDim,
        outCount: hiddenDim,
        kernelSize: 3,
        stride: stride,
        depthwise: true
      )
    )
    layers.append(ConvNormAct(inCount: hiddenDim, outCount: outCount, kernelSize: 1, doAct: false))
    self.layers = TrainableArray(layers)
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> Tensor {
    var h = x
    for layer in self.layers.children { h = layer(h) }
    if useResConnect { return x + h } else { return h }
  }

}

public class MobileNetV2: Trainable {
  @Child var inConv: ConvNormAct
  @Child var layers: TrainableArray<InvertedResidual>
  @Child var outConv: ConvNormAct
  @Child var dropout: Dropout

  public init(inCount: Int, featureCount: Int = 1280) {
    super.init()

    var layers = [InvertedResidual]()

    let descs: [(expand: Int, channels: Int, blocks: Int, stride: Int)] = [
      (1, 16, 1, 1), (6, 24, 2, 2), (6, 32, 3, 2), (6, 64, 4, 2), (6, 96, 3, 1), (6, 160, 3, 2),
      (6, 320, 1, 1),
    ]
    var curChannels = 32
    inConv = ConvNormAct(inCount: inCount, outCount: curChannels, kernelSize: 3, stride: 2)
    for desc in descs {
      for i in 0..<desc.blocks {
        let stride = i == 0 ? desc.stride : 1
        layers.append(
          InvertedResidual(
            inCount: curChannels,
            outCount: desc.channels,
            stride: stride,
            expandRatio: desc.expand
          )
        )
        curChannels = desc.channels
      }
    }
    self.layers = TrainableArray(layers)
    outConv = ConvNormAct(inCount: curChannels, outCount: featureCount, kernelSize: 1)
    dropout = Dropout(dropProb: 0.2)
  }

  @recordCaller private func _callAsFunction(_ x: Tensor) -> Tensor {
    var h = x
    h = inConv(h)
    for layer in layers.children { h = layer(h) }
    h = outConv(h)
    h = h.flatten(startAxis: -2).mean(axis: -1)
    h = dropout(h)
    return h
  }

}
