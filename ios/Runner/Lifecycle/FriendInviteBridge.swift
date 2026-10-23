import Flutter
import Foundation

/// A process-owned pending invite survives scene/Flutter startup ordering.
final class FriendInviteBridge {
    private var channel: FlutterMethodChannel?
    private var state = FriendInvitePendingState()

    func attach(messenger: FlutterBinaryMessenger) {
        guard channel == nil else { return }
        let channel = FlutterMethodChannel(name: "openim_friend_invites", binaryMessenger: messenger)
        self.channel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "takeInvite" else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(self?.state.take())
        }
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let invite = state.receive(url) else { return false }
        channel?.invokeMethod("openInvite", arguments: invite.value) { [weak self] result in
            if result as? Bool == true { self?.state.acknowledge(invite) }
        }
        return true
    }
}
