import Flutter
import ImageIO
import CoreGraphics

public final class QrImageDecoderPlugin: NSObject, FlutterPlugin {
    private let queue = DispatchQueue(label: "99chat.qr.image", qos: .userInitiated)
    private var busy = false // Main-thread ownership.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "99chat/qr_image_decoder", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(QrImageDecoderPlugin(), channel: channel)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "decode" else { result(FlutterMethodNotImplemented); return }
        guard !busy else { result(FlutterError(code: "busy", message: "Busy", details: nil)); return }
        guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
            result(FlutterError(code: "invalidImage", message: "Invalid image", details: nil)); return
        }
        busy = true
        queue.async {
            let reply: Any = autoreleasepool { self.decode(path) }
            DispatchQueue.main.async { self.busy = false; result(reply) }
        }
    }
    private func decode(_ path: String) -> Any {
        func failure(_ code: String) -> FlutterError {
            FlutterError(code: code, message: "Image cannot be decoded", details: nil)
        }
        let url = URL(fileURLWithPath: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return failure("invalidImage") }
        guard size <= 32 * 1024 * 1024 else { return failure("tooLarge") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return failure("invalidImage") }
        guard w <= 32768, h <= 32768, w * h <= 16 * 1024 * 1024 else { return failure("tooLarge") }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return failure("invalidImage") }
        var gray = [UInt8](repeating: 255, count: w * h)
        let rendered = gray.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rendered else { return failure("invalidImage") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("qr-local-\(UUID().uuidString).lum")
        do {
            try Data(gray).write(to: output, options: .atomic)
            return ["path": output.path, "width": w, "height": h,
                    "orientation": props[kCGImagePropertyOrientation] as? Int ?? 1]
        } catch {
            try? FileManager.default.removeItem(at: output)
            return failure("invalidImage")
        }
    }
}
