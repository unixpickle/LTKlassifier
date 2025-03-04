import Cocoa
import UniformTypeIdentifiers

/// Shrink an image down to a maximum side length.
public func shrinkImage(_ data: Data, maxSideLength: Int, quality: Float = 0.85) -> Data? {
  guard let loadedImage = NSImage(data: data) else { return nil }

  guard let representation = loadedImage.representations.first else { return nil }
  let size = CGSize(
    width: CGFloat(representation.pixelsWide),
    height: CGFloat(representation.pixelsHigh)
  )
  let scale = CGFloat(maxSideLength) / min(size.width, size.height)
  let pixelsWide = max(1, Int(scale * size.width))
  let pixelsTall = max(1, Int(scale * size.height))

  let bitsPerComponent = 8
  let bytesPerRow = pixelsWide * 4
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo: CGImageAlphaInfo = .premultipliedLast

  guard
    let context = CGContext(
      data: nil,
      width: pixelsWide,
      height: pixelsTall,
      bitsPerComponent: bitsPerComponent,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    )
  else { return nil }
  let imageRect = CGRect(
    origin: .zero,
    size: CGSize(width: CGFloat(pixelsWide), height: CGFloat(pixelsTall))
  )
  context.clear(imageRect)
  guard let loadedCGImage = loadedImage.cgImage(forProposedRect: nil, context: nil, hints: [:])
  else { return nil }
  context.draw(loadedCGImage, in: imageRect)

  guard let resizedCGImage = context.makeImage() else { return nil }
  let outputData = NSMutableData()
  guard
    let destination = CGImageDestinationCreateWithData(
      outputData,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    )
  else { return nil }
  let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
  CGImageDestinationAddImage(destination, resizedCGImage, options as CFDictionary)
  CGImageDestinationFinalize(destination)
  return outputData as Data
}
