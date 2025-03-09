import Cocoa
import HCBacktrace
import Honeycrisp

/// Load an image and fit it into a square.
public func loadImage(_ data: Data, imageSize: Int, augment: Bool = true, pad: Bool = false)
  -> Tensor?
{
  guard var loadedImage = NSImage(data: data) else { return nil }
  if pad {
    guard let padded = padToSquare(loadedImage) else { return nil }
    loadedImage = padded
  }

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

func padToSquare(_ image: NSImage) -> NSImage? {
  guard let representation = image.representations.first else { return nil }
  let pixelSize = CGSize(
    width: CGFloat(representation.pixelsWide),
    height: CGFloat(representation.pixelsHigh)
  )
  let maxDimension = max(pixelSize.width, pixelSize.height)
  let newSize = CGSize(width: maxDimension, height: maxDimension)
  let newRect = CGRect(origin: .zero, size: newSize)
  let originalRect = CGRect(
    x: (maxDimension - pixelSize.width) / 2,
    y: (maxDimension - pixelSize.height) / 2,
    width: pixelSize.width,
    height: pixelSize.height
  )

  guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: [:]) else {
    return nil
  }

  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo: CGImageAlphaInfo = .premultipliedLast
  guard
    let context = CGContext(
      data: nil,
      width: Int(newSize.width),
      height: Int(newSize.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    )
  else { return nil }

  context.setFillColor(NSColor.white.cgColor)
  context.fill(newRect)
  context.draw(cgImage, in: originalRect)

  guard let newCGImage = context.makeImage() else { return nil }

  let newRepresentation = NSBitmapImageRep(cgImage: newCGImage)

  let newImage = NSImage(size: NSSize(width: newSize.width, height: newSize.height))
  newImage.addRepresentation(newRepresentation)
  return newImage
}
