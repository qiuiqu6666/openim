import Flutter
import Foundation
import Photos

/// PhotoKit original resources only. No permission request, UIImage/JPEG
/// conversion, or iCloud fetch. Each export is an owned, cancellable disk lease.
final class DeviceSyncOriginalsBridge {
    private final class Export {
        let url: URL
        let handle: FileHandle
        let result: FlutterResult
        let limit: Int64
        var nativeID: PHAssetResourceDataRequestID?
        var bytes: Int64 = 0

        init(url: URL, handle: FileHandle, limit: Int64,
             result: @escaping FlutterResult) {
            self.url = url
            self.handle = handle
            self.limit = limit
            self.result = result
        }
    }

    private let channel: FlutterMethodChannel
    private let queue = DispatchQueue(label: "openim.device-sync.originals", qos: .utility)
    private let queueIdentity = DispatchSpecificKey<UInt8>()
    private let manager = PHAssetResourceManager.default()
    // Accessed only on queue, including all Photos callbacks and cancellation.
    private var pending: [String: Export] = [:]
    private var leases: [String: URL] = [:]
    private let directory: URL

    init(messenger: FlutterBinaryMessenger) {
        directory = FileManager.default.urls(for: .cachesDirectory,
                                             in: .userDomainMask)[0]
            .appendingPathComponent("DeviceSyncOriginals", isDirectory: true)
        channel = FlutterMethodChannel(name: "openim_device_sync_originals",
                                       binaryMessenger: messenger)
        queue.setSpecific(key: queueIdentity, value: 1)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "unavailable", message: nil, details: nil))
                return
            }
            self.queue.async { self.handle(call, result: result) }
        }
        queue.async { [weak self] in self?.removeAbandonedExports() }
    }

    private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
        DispatchQueue.main.async { result(value) }
    }

    private func serializeChunk(_ operation: () -> Void) {
        // PhotoKit documents an arbitrary serial callback queue. Also tolerate a
        // synchronous callback on our queue without dispatching sync to itself.
        if DispatchQueue.getSpecific(key: queueIdentity) != nil { operation() }
        else { queue.sync(execute: operation) }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let requestID = args["requestID"] as? String,
              !requestID.isEmpty, requestID.count <= 100 else {
            reply(result, FlutterError(code: "arguments", message: nil, details: nil))
            return
        }
        switch call.method {
        case "open":
            guard let assetID = args["assetID"] as? String,
                  let kind = args["kind"] as? String,
                  kind == "image" || kind == "video" else {
                reply(result, FlutterError(code: "arguments", message: nil, details: nil))
                return
            }
            open(requestID, assetID: assetID, kind: kind, result: result)
        case "cancel", "release":
            cancel(requestID)
            if let url = leases.removeValue(forKey: requestID) { removeOwned(url) }
            reply(result, nil)
        default:
            reply(result, FlutterMethodNotImplemented)
        }
    }

    private func hasReadAccess() -> Bool {
        if #available(iOS 14, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            return status == .authorized || status == .limited
        }
        return PHPhotoLibrary.authorizationStatus() == .authorized
    }

    private func open(_ requestID: String, assetID: String, kind: String,
                      result: @escaping FlutterResult) {
        guard hasReadAccess() else {
            reply(result, FlutterError(code: "permission_denied", message: nil, details: nil))
            return
        }
        guard pending.isEmpty, pending[requestID] == nil, leases[requestID] == nil else {
            reply(result, FlutterError(code: "busy", message: "Original export is busy", details: nil))
            return
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            .firstObject else {
            reply(result, FlutterError(code: "not_found", message: nil, details: nil))
            return
        }
        let expectedMedia: PHAssetMediaType = kind == "video" ? .video : .image
        let resourceType: PHAssetResourceType = kind == "video" ? .video : .photo
        guard asset.mediaType == expectedMedia,
              let resource = PHAssetResource.assetResources(for: asset)
                .first(where: { $0.type == resourceType }) else {
            reply(result, FlutterError(code: "not_found", message: nil, details: nil))
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true)
            // Never use assetID or filename as a path: they may contain slashes.
            let url = directory.appendingPathComponent("original-\(UUID().uuidString).data")
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw NSError(domain: "DeviceSync", code: 1)
            }
            let handle: FileHandle
            do { handle = try FileHandle(forWritingTo: url) }
            catch { removeOwned(url); throw error }
            let export = Export(url: url, handle: handle,
                                limit: kind == "video" ? 512 * 1024 * 1024 : 30 * 1024 * 1024,
                                result: result)
            pending[requestID] = export
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            export.nativeID = manager.requestData(for: resource, options: options,
                dataReceivedHandler: { [weak self, weak export] data in
                    guard let self = self, let export = export else { return }
                    // Backpressure: write each PhotoKit chunk before accepting
                    // the next, rather than enqueueing all bytes in memory.
                    self.serializeChunk {
                        guard self.pending[requestID] === export else { return }
                        export.bytes += Int64(data.count)
                        guard export.bytes <= export.limit else {
                            self.fail(requestID, code: "too_large", message: nil)
                            return
                        }
                        do {
                            if #available(iOS 13.4, *) { try export.handle.write(contentsOf: data) }
                            else { export.handle.write(data) }
                        } catch {
                            self.fail(requestID, code: "io", message: error.localizedDescription)
                        }
                    }
                }, completionHandler: { [weak self, weak export] error in
                    guard let self = self, let export = export else { return }
                    self.queue.async {
                        guard self.pending[requestID] === export else { return }
                        if let error = error {
                            self.fail(requestID, code: "not_local", message: error.localizedDescription)
                        } else if export.bytes == 0 {
                            self.fail(requestID, code: "not_found", message: nil)
                        } else {
                            self.pending.removeValue(forKey: requestID)
                            self.close(export.handle)
                            self.leases[requestID] = export.url
                            self.reply(export.result, ["path": export.url.path])
                        }
                    }
                })
        } catch {
            reply(result, FlutterError(code: "io", message: error.localizedDescription, details: nil))
        }
    }

    private func fail(_ requestID: String, code: String, message: String?) {
        guard let export = pending.removeValue(forKey: requestID) else { return }
        if let nativeID = export.nativeID { manager.cancelDataRequest(nativeID) }
        close(export.handle)
        removeOwned(export.url)
        reply(export.result, FlutterError(code: code, message: message, details: nil))
    }

    private func cancel(_ requestID: String) {
        fail(requestID, code: "cancelled", message: "Original export cancelled")
    }

    private func close(_ handle: FileHandle) {
        if #available(iOS 13.0, *) { try? handle.close() }
        else { handle.closeFile() }
    }

    private func removeOwned(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              url.lastPathComponent.hasPrefix("original-"), url.pathExtension == "data" else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func removeAbandonedExports() {
        // Only our dedicated files; no library path or another cache is removed.
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { removeOwned(file) }
    }
}
