import Cocoa
import HCBacktrace
import Honeycrisp

/// Load an image and fit it into a square.
public func loadImage(_ data: Data, imageSize: Int) -> Tensor? {
  guard let loadedImage = NSImage(data: data) else { return nil }

  let bitsPerComponent = 8
  let bytesPerRow = imageSize * 4
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo: CGImageAlphaInfo = .premultipliedLast

  guard
    let context = CGContext(
      data: nil,
      width: imageSize,
      height: imageSize,
      bitsPerComponent: bitsPerComponent,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    )
  else { return nil }
  context.clear(CGRect(origin: .zero, size: CGSize(width: imageSize, height: imageSize)))

  let size = loadedImage.size
  let scale = CGFloat(imageSize) / max(size.width, size.height)
  let scaledSize = CGSize(width: scale * size.width, height: scale * size.height)
  let x = floor((CGFloat(imageSize) - scaledSize.width) / 2.0)
  let y = floor((CGFloat(imageSize) - scaledSize.width) / 2.0)
  let imageRect = CGRect(origin: CGPoint(x: x, y: y), size: scaledSize)
  guard let loadedCGImage = loadedImage.cgImage(forProposedRect: nil, context: nil, hints: [:])
  else { return nil }
  context.draw(loadedCGImage, in: imageRect)

  guard let data = context.data else { return nil }

  let buffer = data.bindMemory(to: UInt8.self, capacity: imageSize * (bytesPerRow / 4) * 3)
  var floats = [Float]()
  for i in 0..<(imageSize * imageSize * 4) {
    if i % 4 != 3 { floats.append(Float(buffer[i]) / 255.0) }
  }
  return Tensor(data: floats, shape: [imageSize, imageSize, 3]).move(axis: -1, to: 0)
}
