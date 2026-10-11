import CallKit
import Flutter
import Foundation
import PushKit

/// PushKit/CallKit stay alive before Flutter is ready. Only a successfully
/// authenticated Dart session may bind calls or upload the in-memory token.
final class IOSVoIPCallBridge: NSObject, PKPushRegistryDelegate {
    private static let accountDefaultsKey = "openim.callkit.authorizedAccountID"
    private let coordinator = CallKitCallCoordinator()
    private var registry: PKPushRegistry?
    private var channel: FlutterMethodChannel?
    private var accountID = ""
    private var sessionKey = ""
    private var retiredAudioSessionKey = ""
    private var acceptsIncoming = false
    private var ready = false
    private var token = ""
    private var pendingEvents: [[String: Any]] = []

    override init() {
        super.init()
        accountID = UserDefaults.standard.string(forKey: Self.accountDefaultsKey) ?? ""
        acceptsIncoming = !accountID.isEmpty
        coordinator.onEvent = { [weak self] event in self?.deliver(event) }
        coordinator.onRecordEnded = { [weak self] record in
            self?.pendingEvents.removeAll {
                $0["callUUID"] as? String == record.uuid.uuidString
                    && ["incoming", "answer", "end", "mute", "started"].contains($0["type"] as? String ?? "")
            }
        }
    }

    func start() {
        guard registry == nil else { return }
        let pushRegistry = PKPushRegistry(queue: .main)
        registry = pushRegistry
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = acceptsIncoming ? [.voIP] : []
    }

    func attach(messenger: FlutterBinaryMessenger) {
        guard channel == nil else { return }
        let bridge = FlutterMethodChannel(name: "ios_voip_callkit", binaryMessenger: messenger)
        channel = bridge
        bridge.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            self.handle(call, result: result)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP, registry === self.registry, acceptsIncoming else { return }
        token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        if !sessionKey.isEmpty { channel?.invokeMethod("onVoipToken", arguments: tokenMetadata()) }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP, registry === self.registry else { return }
        token = ""
        deliver(["type": "tokenInvalidated", "accountID": accountID, "sessionKey": sessionKey])
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        var raw: [String: Any] = [:]
        payload.dictionaryPayload.forEach { raw[String(describing: $0.key)] = $0.value }
        let incoming = VoIPCallPayload(raw)
        let usable = registry === self.registry && acceptsIncoming && incoming.valid
            && incoming.accountID == accountID && incoming.deadline!.timeIntervalSinceNow > 0
        // Do not await SDK login, Flutter, avatar data, or any network operation.
        // Even unusable pushes must be reported before their completion.
        var completed = false
        coordinator.reportIncoming(incoming, sessionKey: sessionKey, usable: usable, mustReportDuplicate: true) { _ in
            guard !completed else { return }
            completed = true
            completion()
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "install":
            start()
            result(nil)
        case "setSession":
            let nextAccount = VoIPCallPayload.string(args, ["accountID"])
            let nextKey = VoIPCallPayload.string(args, ["sessionKey"])
            guard !nextAccount.isEmpty, !nextKey.isEmpty else { result(Self.error("invalid_session")); return }
            ready = false
            if nextAccount != accountID {
                coordinator.endAll(keepingColdCalls: false)
                pendingEvents.removeAll()
            } else if !sessionKey.isEmpty && sessionKey != nextKey {
                coordinator.endAll(keepingColdCalls: true)
                pendingEvents.removeAll { $0["sessionKey"] as? String != "" }
            }
            accountID = nextAccount
            sessionKey = nextKey
            acceptsIncoming = true
            UserDefaults.standard.set(nextAccount, forKey: Self.accountDefaultsKey)
            coordinator.adoptColdCalls(accountID: nextAccount, sessionKey: nextKey)
            pendingEvents = pendingEvents.compactMap { event in
                guard event["accountID"] as? String == nextAccount else { return nil }
                var adopted = event
                if adopted["sessionKey"] as? String == "" { adopted["sessionKey"] = nextKey }
                return adopted["sessionKey"] as? String == nextKey ? adopted : nil
            }
            start()
            registry?.desiredPushTypes = [.voIP]
            if let cached = registry?.pushToken(for: .voIP) { token = cached.map { String(format: "%02x", $0) }.joined() }
            result(nil)
        case "pauseSession":
            let requested = args["sessionKey"] as? String ?? ""
            let bound = !sessionKey.isEmpty && requested == sessionKey
            let unbound = sessionKey.isEmpty && (requested.isEmpty || (!retiredAudioSessionKey.isEmpty && requested == retiredAudioSessionKey))
            guard bound || unbound else { result(Self.error("session_changed")); return }
            let logout = args["logout"] as? Bool == true
            let hadSession = !sessionKey.isEmpty
            if hadSession { retiredAudioSessionKey = sessionKey }
            ready = false
            sessionKey = ""
            if logout {
                acceptsIncoming = false
                accountID = ""
                token = ""
                UserDefaults.standard.removeObject(forKey: Self.accountDefaultsKey)
                registry?.desiredPushTypes = []
                coordinator.endAll(keepingColdCalls: false)
                pendingEvents.removeAll()
            } else {
                if hadSession { acceptsIncoming = false }
                coordinator.endAll(keepingColdCalls: true)
                pendingEvents.removeAll { $0["sessionKey"] as? String != "" }
            }
            // Keep a cold answered call's manual gate intact during SDK login
            // preparation; authenticated old media must stop immediately.
            if hadSession || logout { coordinator.quarantineAudio() }
            result(nil)
        case "setEventHandlerReady":
            ready = args["ready"] as? Bool == true && !sessionKey.isEmpty
            result(nil)
        case "drainPendingEvents":
            guard !sessionKey.isEmpty else { result([]); return }
            let events = pendingEvents.filter { $0["accountID"] as? String == accountID && $0["sessionKey"] as? String == sessionKey }
            pendingEvents.removeAll()
            result(events)
        case "getCachedTokens":
            result(tokenMetadata())
        case "getState":
            result(["accountID": accountID, "sessionKey": sessionKey, "audioActive": coordinator.audioActive,
                    "calls": coordinator.calls.map { record -> [String: Any] in
                        var state = record.event("state")
                        state["status"] = record.status
                        state["outgoing"] = record.outgoing
                        state["payload"] = record.payload
                        return state
                    }])
        case "releaseAudioSession":
            let requested = args["sessionKey"] as? String ?? ""
            let current = !sessionKey.isEmpty && requested == sessionKey
            let retired = sessionKey.isEmpty && !retiredAudioSessionKey.isEmpty && requested == retiredAudioSessionKey
            guard current || retired else { result(false); return }
            let released = coordinator.releaseAudioSession()
            if released && retired { retiredAudioSessionKey = "" }
            result(released)
        case "reportIncomingCall":
            guard matches(args) else { result(Self.error("session_changed")); return }
            let incoming = VoIPCallPayload(args["payload"] as? [String: Any] ?? args)
            guard incoming.valid, incoming.accountID == accountID, incoming.deadline!.timeIntervalSinceNow > 0 else {
                result(Self.error("invalid_invitation")); return
            }
            if coordinator.wasEnded(roomID: incoming.roomID, accountID: accountID) {
                result(Self.error("call_ended")); return
            }
            let existing = coordinator.call(roomID: incoming.roomID, accountID: accountID)
            if !coordinator.calls.isEmpty && (existing == nil || existing?.sessionKey != sessionKey) {
                result(Self.error("call_busy")); return
            }
            coordinator.reportIncoming(incoming, sessionKey: sessionKey, usable: true) { result(Self.resultError($0)) }
        case "startOutgoingCall":
            guard matches(args), let room = nonemptyRoom(args) else { result(Self.error("session_changed")); return }
            let handle = VoIPCallPayload.string(args, ["handle", "calleeID", "calleeId"])
            let name = VoIPCallPayload.string(args, ["displayName"])
            guard !handle.isEmpty else { result(Self.error("invalid_handle")); return }
            coordinator.startOutgoing(roomID: room, accountID: accountID, sessionKey: sessionKey,
                                      handle: handle, displayName: name.isEmpty ? handle : name,
                                      hasVideo: args["hasVideo"] as? Bool == true) { result(Self.resultError($0)) }
        case "updateDisplayName":
            guard matches(args), let room = nonemptyRoom(args),
                  let record = coordinator.call(roomID: room, accountID: accountID),
                  record.sessionKey == sessionKey else { result(nil); return }
            let name = VoIPCallPayload.string(args, ["displayName"])
            coordinator.updateDisplayName(record, name: name)
            result(nil)
        case "completeAction":
            guard matches(args), let rawID = args["actionID"] as? String, let id = UUID(uuidString: rawID) else {
                result(Self.error("session_changed")); return
            }
            result(coordinator.completeAction(actionID: id, accountID: accountID, sessionKey: sessionKey,
                                              succeeded: args["succeeded"] as? Bool == true))
        case "markConnected", "endCall", "setAudioEnabled", "requestAnswer", "requestMute", "setSpeakerphone":
            guard matches(args), let room = nonemptyRoom(args) else {
                result(Self.error("session_changed")); return
            }
            guard let record = coordinator.call(roomID: room, accountID: accountID) else {
                if call.method == "endCall" || call.method == "markConnected" { result(nil) }
                else { result(false) }
                return
            }
            guard record.sessionKey == sessionKey else { result(Self.error("session_changed")); return }
            if call.method == "markConnected" { coordinator.markConnected(record); result(nil) }
            else if call.method == "requestAnswer" { coordinator.requestAnswer(record) { result($0) } }
            else if call.method == "requestMute" {
                guard let muted = args["muted"] as? Bool else { result(false); return }
                coordinator.requestMute(record, muted: muted) { result($0) }
            } else if call.method == "setSpeakerphone" {
                guard let enabled = args["enabled"] as? Bool else { result(false); return }
                result(coordinator.setSpeakerphone(enabled, record: record))
            }
            else if call.method == "endCall" {
                coordinator.end(record, reason: Self.endReason(args["reason"] as? String))
                result(nil)
            } else { result(coordinator.setAudioEnabled(args["enabled"] as? Bool == true, record: record)) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func matches(_ args: [String: Any]) -> Bool {
        return acceptsIncoming && !sessionKey.isEmpty && args["sessionKey"] as? String == sessionKey
            && (args["accountID"] == nil || args["accountID"] as? String == accountID)
    }

    private func nonemptyRoom(_ args: [String: Any]) -> String? {
        let room = VoIPCallPayload.string(args, ["roomID"])
        return room.isEmpty ? nil : room
    }

    private func deliver(_ event: [String: Any]) {
        guard event["accountID"] as? String == accountID, !accountID.isEmpty else { return }
        if ready, pendingEvents.isEmpty, !sessionKey.isEmpty,
           event["sessionKey"] as? String == sessionKey, let channel = channel {
            channel.invokeMethod("onEvent", arguments: event)
        } else {
            pendingEvents.append(event)
            if pendingEvents.count > 64 { pendingEvents.removeFirst() }
        }
    }

    private func tokenMetadata() -> [String: String] {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        return ["voipToken": token, "bundleId": bundle, "apsEnvironment": IOSAPNsPushBridge.apnsEnvironment(),
                "voipTopic": bundle + ".voip", "accountID": accountID, "sessionKey": sessionKey]
    }

    private static func endReason(_ reason: String?) -> CXCallEndedReason {
        switch reason {
        case "unanswered", "timeout": return .unanswered
        case "answeredElsewhere": return .answeredElsewhere
        case "declinedElsewhere": return .declinedElsewhere
        case "failed", "networkError": return .failed
        default: return .remoteEnded
        }
    }

    private static func error(_ code: String) -> FlutterError { return FlutterError(code: code, message: code, details: nil) }
    private static func resultError(_ error: Error?) -> Any? {
        guard let error = error else { return nil }
        let nativeError = error as NSError
        return FlutterError(code: "callkit_failed", message: "CallKit could not complete the request",
                            details: ["domain": nativeError.domain, "code": nativeError.code])
    }
}
