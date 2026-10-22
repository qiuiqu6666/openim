import AVFoundation
import Flutter

/// Media routing is independent of AVPlayer lifetime and position.
final class MediaAudioBridge {
    private let channel: FlutterMethodChannel
    private let session = AVAudioSession.sharedInstance()
    private var kind: String?
    private var speaker = true
    private var interrupted = false
    private var observers: [NSObjectProtocol] = []

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "openim/media_audio", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            if call.method == "snapshot" {
                result(["kind": self.kind ?? "", "speaker": self.speaker,
                        "outputs": self.session.currentRoute.outputs.map { $0.portType.rawValue }])
                return
            }
            guard call.method == "configure" else { result(FlutterMethodNotImplemented); return }
            let args = call.arguments as? [String: Any] ?? [:]
            let requested = args["kind"] as? String
            self.speaker = args["output"] as? String != "earpiece"
            do {
                if requested == nil {
                    let previous = self.kind
                    self.kind = nil
                    if !self.interrupted && previous == "voice" && self.session.category == .playAndRecord { try self.session.overrideOutputAudioPort(.none) }
                    if previous != nil && !self.interrupted { try self.session.setActive(false, options: .notifyOthersOnDeactivation) }
                    self.interrupted = false
                } else if requested == "recording" {
                    // The existing record plugin owns microphone session configuration.
                    self.kind = requested
                } else {
                    if self.interrupted { throw NSError(domain: "MediaAudioBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio session interrupted"]) }
                    self.kind = requested
                    if requested == "voice" {
                        // Keep the category stable during live output switching.
                        var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
                        if self.speaker { options.insert(.defaultToSpeaker) }
                        try self.session.setCategory(.playAndRecord, mode: .default, options: options)
                        try self.session.setActive(true)
                        try self.applyVoiceRoute()
                    } else {
                        try self.session.setCategory(.playback, mode: .moviePlayback)
                        try self.session.setActive(true)
                    }
                }
                result(nil)
            } catch {
                result(FlutterError(code: "audio_route", message: error.localizedDescription, details: nil))
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            if value == AVAudioSession.InterruptionType.began.rawValue {
                self?.interrupted = true
                self?.interrupt()
            } else {
                // Allow a later explicit play request without automatically resuming.
                self?.interrupted = false
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let self = self, self.kind == "voice",
                  let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: value) else { return }
            if reason == .oldDeviceUnavailable {
                // Never unexpectedly expose private audio after headphones disconnect.
                self.interrupt()
            } else if reason == .newDeviceAvailable {
                do { try self.applyVoiceRoute() } catch { self.interrupt() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in self?.interrupt() })
    }
    private func applyVoiceRoute() throws {
        let external = session.currentRoute.outputs.contains {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
        try session.overrideOutputAudioPort(external ? .none : (speaker ? .speaker : .none))
    }
    private func interrupt() {
        guard kind != nil, kind != "recording" else { return }
        channel.invokeMethod("interrupted", arguments: nil)
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
