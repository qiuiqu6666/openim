import Flutter
import ImageIO
import Vision

enum ImageTextRecognizer {
    static func recognize(_ path: String) -> Any {
        let failure = FlutterError(code: "textUnavailable", message: "Text recognition failed", details: nil)
        let url = URL(fileURLWithPath: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 32768, h <= 32768, w * h <= 16 * 1024 * 1024
        else { return failure }
        let orientation = CGImagePropertyOrientation(rawValue: (props[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        // Wallet strings are not natural language: never autocorrect characters.
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(url: url, orientation: orientation, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch { return failure }
    }
}
