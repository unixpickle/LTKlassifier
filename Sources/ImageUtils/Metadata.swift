import Cocoa

/// Get the size of the image without decoding it.
///
/// This can be used to safely verify an untrusted image before loading it.
public func getImageSize(_ data: Data) -> CGSize? {
  guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
    let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
  else { return nil }
  return CGSize(width: width, height: height)
}
