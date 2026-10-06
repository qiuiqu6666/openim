import AVKit
import Flutter
import UIKit

/// Uses the real remote WebRTC renderer, not a synthetic video for arbitrary UI.
final class CallPictureInPictureBridge: NSObject, AVPictureInPictureControllerDelegate {
    private let channel: FlutterMethodChannel
    private weak var sourceController: FlutterViewController?
    private var pip: AVPictureInPictureController?
    private var contentController: UIViewController?
    private var frameView: CallVideoFrameView?
    private var session: String?
    private var trackID: String?
    private var enabled = false
    private var stopping = false
    private var restoring = false
    private var cameraSupported = false
    private var possibleObserver: NSKeyValueObservation?

    init(controller: FlutterViewController) {
        sourceController = controller
        channel = FlutterMethodChannel(name: "openim_call_pip", binaryMessenger: controller.binaryMessenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(false); return }
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "configure":
                result(self.configure(args))
            case "enter":
                result(self.matches(args) && self.enter())
            case "stop":
                if self.matches(args) { self.stop() }
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private var supported: Bool {
        if #available(iOS 15.0, *) {
            return AVPictureInPictureController.isPictureInPictureSupported()
        }
        return false
    }

    private func matches(_ args: [String: Any]) -> Bool {
        session != nil && args["session"] as? String == session
    }

    private func configure(_ args: [String: Any]) -> [String: Bool] {
        guard args["enabled"] as? Bool == true,
              let requestedSession = args["session"] as? String,
              let requestedTrack = args["remoteVideoTrackId"] as? String,
              !requestedTrack.isEmpty,
              supported,
              let source = sourceController?.view,
              source.window != nil else {
            stop()
            // Audio-only calls have no video source; retain the application
            // mini window rather than representing an avatar as fake video.
            return capability(ready: false)
        }
        if session == requestedSession, pip != nil {
            // Keep an active AVKit window while LiveKit replaces its remote
            // subscription; the frame view invalidates samples from old tracks.
            guard let view = frameView, view.attachRemoteTrack(requestedTrack) else {
                stop()
                return capability(ready: false)
            }
            trackID = requestedTrack
            cameraSupported = CallVideoFrameView.enableBackgroundCamera()
            return capability(ready: view.hasVideoFrame)
        }
        stop()
        guard #available(iOS 15.0, *) else { return capability(ready: false) }
        let view = CallVideoFrameView(frame: CGRect(x: 0, y: 0, width: 360, height: 640))
        guard view.attachRemoteTrack(requestedTrack) else {
            return capability(ready: false)
        }
        let content = AVPictureInPictureVideoCallViewController()
        let width = max(1, (args["aspectWidth"] as? NSNumber)?.doubleValue ?? 9)
        let height = max(1, (args["aspectHeight"] as? NSNumber)?.doubleValue ?? 16)
        content.preferredContentSize = CGSize(width: width * 40, height: height * 40)
        content.view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.view.topAnchor),
            view.bottomAnchor.constraint(equalTo: content.view.bottomAnchor)
        ])
        let sourceContent = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: source, contentViewController: content)
        let controller = AVPictureInPictureController(contentSource: sourceContent)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        session = requestedSession
        trackID = requestedTrack
        enabled = true
        stopping = false
        restoring = false
        frameView = view
        contentController = content
        pip = controller
        cameraSupported = CallVideoFrameView.enableBackgroundCamera()
        // Native AVKit owns background auto-entry once a real video frame and
        // a supported, active video call content source have become available.
        possibleObserver = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
            [weak self, weak controller] _, _ in
            guard let self = self, self.enabled, let controller = controller,
                  controller === self.pip else { return }
            if !controller.isPictureInPicturePossible, !controller.isPictureInPictureActive {
                self.emit("failed")
            }
        }
        return capability(ready: view.hasVideoFrame)
    }

    private func capability(ready: Bool) -> [String: Bool] {
        ["supported": supported && enabled,
         "ready": ready,
         "backgroundCameraSupported": cameraSupported]
    }

    private func enter() -> Bool {
        guard enabled, let controller = pip,
              frameView?.hasVideoFrame == true,
              controller.isPictureInPicturePossible else { return false }
        if controller.isPictureInPictureActive { return true }
        emit("entering")
        controller.startPictureInPicture()
        return true
    }

    private func stop() {
        stopping = true
        enabled = false
        session = nil
        trackID = nil
        possibleObserver = nil
        if let controller = pip {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            controller.delegate = nil
            if controller.isPictureInPictureActive { controller.stopPictureInPicture() }
        }
        frameView?.detach()
        frameView?.removeFromSuperview()
        frameView = nil
        contentController = nil
        pip = nil
        cameraSupported = false
    }

    private func emit(_ phase: String) {
        guard enabled, let current = session else { return }
        channel.invokeMethod("state", arguments: ["session": current, "phase": phase])
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard controller === pip else { return }
        restoring = false
        emit("entering")
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        if controller === pip { emit("active") }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                   failedToStartPictureInPictureWithError error: Error) {
        if controller === pip { emit("failed") }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                   restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard controller === pip, enabled else { completionHandler(false); return }
        restoring = true
        emit("restored")
        // The Flutter call overlay remains mounted throughout PiP.
        completionHandler(sourceController?.view.window != nil)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        guard controller === pip, enabled, !stopping else { return }
        if restoring {
            restoring = false
        } else {
            emit("closed")
            stop()
        }
    }

    func dispose() {
        stop()
        channel.setMethodCallHandler(nil)
    }

    deinit { frameView?.detach() }
}
