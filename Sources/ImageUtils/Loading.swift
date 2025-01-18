import Cocoa
import HCBacktrace
import Honeycrisp

/// Load an image and fit it into a square.
public func loadImage(_ data: Data, imageSize: Int, augment: Bool = true) -> Tensor? {
  guard let loadedImage = NSImage(data: data) else { return nil }

  guard let representation = loadedImage.representations.first else { return nil }

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

  // Randomly crop the original image.
  let size = CGSize(
    width: CGFloat(representation.pixelsWide),
    height: CGFloat(representation.pixelsHigh)
  )
  let cropWidth =
    if augment { CGFloat.random(in: size.width * 0.9...size.width) } else { size.width }
  let cropHeight =
    if augment { CGFloat.random(in: size.height * 0.9...size.height) } else { size.height }
  let cropX = CGFloat.random(in: 0...(size.width - cropWidth))
  let cropY = CGFloat.random(in: 0...(size.height - cropHeight))
  let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

  let scale = CGFloat(imageSize) / max(cropWidth, cropHeight)
  let scaledSize = CGSize(width: scale * cropWidth, height: scale * cropHeight)
  let x = round((CGFloat(imageSize) - scaledSize.width) / 2.0)
  let y = round((CGFloat(imageSize) - scaledSize.height) / 2.0)
  let imageRect = CGRect(origin: CGPoint(x: x, y: y), size: scaledSize)
  guard let loadedCGImage = loadedImage.cgImage(forProposedRect: nil, context: nil, hints: [:])
  else { return nil }
  guard let croppedCGImage = loadedCGImage.cropping(to: cropRect) else { return nil }
  context.draw(croppedCGImage, in: imageRect)

  guard let data = context.data else { return nil }

  let buffer = data.bindMemory(to: UInt8.self, capacity: imageSize * (bytesPerRow / 4) * 3)
  var floats = [Float]()
  for i in 0..<(imageSize * imageSize * 4) {
    if i % 4 != 3 { floats.append(Float(buffer[i]) / 255.0) }
  }
  return Tensor(data: floats, shape: [imageSize, imageSize, 3]).move(axis: -1, to: 0)
}
