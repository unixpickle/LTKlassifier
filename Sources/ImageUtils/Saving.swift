import Cocoa
import HCBacktrace
import Honeycrisp

enum ImageError: Error { case encodePNG }

/// Encode a CHW tensor as an image.
public func encodeImage(_ tensor: Tensor) async throws -> Data {
  assert(tensor.shape.count == 3)
  assert(tensor.shape[0] == 3, "tensor must be RGB")
  let tensor = tensor.move(axis: 0, to: -1)
  let height = tensor.shape[0]
  let width = tensor.shape[1]

  let floats = try await tensor.floats()

  let bytesPerRow = width * 4
  var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
  for (i, f) in floats.enumerated() { buffer[i] = UInt8(floor(min(1, max(0, f)) * 255.999)) }

  return try buffer.withUnsafeMutableBytes { ptr in
    var ptr: UnsafeMutablePointer<UInt8>? = ptr.bindMemory(to: UInt8.self).baseAddress!
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: &ptr,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 3,
      hasAlpha: false,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: width * 3,
      bitsPerPixel: 24
    )!
    if let result = rep.representation(using: .png, properties: [:]) {
      return result
    } else {
      throw ImageError.encodePNG
    }
  }
}
