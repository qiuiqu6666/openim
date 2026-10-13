import AVFoundation
import CallKit
import Foundation

final class CallKitCallRecord {
    let uuid: UUID
    let roomID: String
    let accountID: String
    var sessionKey: String
    let payload: [String: Any]
    let hasVideo: Bool
    let outgoing: Bool
    var status = "ringing"
    var reported = false
    var serverAccepted = false
    var expiry: DispatchWorkItem?

    init(uuid: UUID = UUID(), roomID: String, accountID: String, sessionKey: String,
         payload: [String: Any], hasVideo: Bool, outgoing: Bool) {
        self.uuid = uuid
        self.roomID = roomID
        self.accountID = accountID
        self.sessionKey = sessionKey
        self.payload = payload
        self.hasVideo = hasVideo
        self.outgoing = outgoing
    }

    func event(_ type: String) -> [String: Any] {
        return ["type": type, "accountID": accountID, "sessionKey": sessionKey,
                "roomID": roomID, "callUUID": uuid.uuidString, "status": status,
                "outgoing": outgoing, "hasVideo": hasVideo, "payload": payload]
    }
}

/// One system provider and one active business call. Unusable VoIP pushes are
/// still reported, then immediately ended, without reaching the SDK account.
final class CallKitCallCoordinator: NSObject, CXProviderDelegate {
    private let provider: CXProvider
    private let controller = CXCallController()
    private let audio = CallKitAudioSession()
    private var records: [UUID: CallKitCallRecord] = [:]
    private var actions: [UUID: (CXAction, CallKitCallRecord, DispatchWorkItem)] = [:]
    private var completedActions: [UUID: (accountID: String, sessionKey: String, succeeded: Bool)] = [:]
    private var completedActionOrder: [UUID] = []
    private var endedRooms: [String: Date] = [:]
    var onEvent: (([String: Any]) -> Void)?
    var onRecordEnded: ((CallKitCallRecord) -> Void)?

    override init() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "99chat"
        let configuration = CXProviderConfiguration(localizedName: name)
        configuration.supportsVideo = true
        configuration.supportedHandleTypes = [.generic]
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    var audioActive: Bool { return audio.active }
    var calls: [CallKitCallRecord] { return Array(records.values) }

    func call(roomID: String, accountID: String) -> CallKitCallRecord? {
        return records.values.first { $0.roomID == roomID && $0.accountID == accountID }
    }

    func wasEnded(roomID: String, accountID: String) -> Bool {
        endedRooms = endedRooms.filter { Date().timeIntervalSince($0.value) < 300 }
        return endedRooms[accountID + "\n" + roomID] != nil
    }

    func reportIncoming(_ payload: VoIPCallPayload, sessionKey: String,
                        usable: Bool, mustReportDuplicate: Bool = false, completion: @escaping (Error?) -> Void) {
        if usable, let existing = call(roomID: payload.roomID, accountID: payload.accountID) {
            if !mustReportDuplicate { updateDisplayName(existing, name: payload.callerName); completion(nil); return }
            // Every legacy PushKit delivery must call report, including repeats.
            // Reusing the UUID cannot create another business call or end this one.
            let duplicate = CXCallUpdate()
            duplicate.remoteHandle = CXHandle(type: .generic, value: payload.callerID)
            duplicate.localizedCallerName = payload.callerName
            duplicate.hasVideo = payload.hasVideo
            provider.reportNewIncomingCall(with: existing.uuid, update: duplicate, completion: completion)
            return
        }
        // A discard gets its own UUID and cannot replace the real active room.
        let accepted = usable && records.isEmpty && !wasEnded(roomID: payload.roomID, accountID: payload.accountID)
        let record = CallKitCallRecord(roomID: payload.roomID, accountID: payload.accountID,
                                      sessionKey: sessionKey, payload: payload.raw,
                                      hasVideo: payload.hasVideo, outgoing: false)
        if accepted { records[record.uuid] = record }
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: accepted ? payload.callerID : "99chat")
        update.localizedCallerName = accepted ? payload.callerName : "99chat"
        update.hasVideo = payload.hasVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportNewIncomingCall(with: record.uuid, update: update) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { completion(error); return }
                let stillCurrent = self.records[record.uuid] === record
                if !accepted || !stillCurrent {
                    if error == nil { self.provider.reportCall(with: record.uuid, endedAt: Date(), reason: .failed) }
                } else if let error = error {
                    self.finish(record, reason: .failed, reportToSystem: false)
                    var event = record.event("reportFailed")
                    event["domain"] = (error as NSError).domain
                    event["code"] = (error as NSError).code
                    self.onEvent?(event)
                } else {
                    record.reported = true
                    var event = record.event("incoming")
                    event["payload"] = record.payload
                    self.onEvent?(event)
                    if record.status == "ringing" { self.scheduleExpiry(record, deadline: payload.deadline!) }
                }
                completion(error)
            }
        }
    }

    func startOutgoing(roomID: String, accountID: String, sessionKey: String,
                       handle: String, displayName: String, hasVideo: Bool,
                       completion: @escaping (Error?) -> Void) {
        if let existing = call(roomID: roomID, accountID: accountID), existing.sessionKey == sessionKey {
            completion(nil)
            return
        }
        guard records.isEmpty else { completion(Self.error("call_busy")); return }
        let record = CallKitCallRecord(roomID: roomID, accountID: accountID, sessionKey: sessionKey,
                                      payload: [:], hasVideo: hasVideo, outgoing: true)
        record.status = "connecting"
        records[record.uuid] = record
        // Fence WebRTC before the Flutter caller can connect the room. The
        // transaction completion may precede perform(CXStartCallAction).
        do { try audio.prepare(hasVideo: hasVideo) }
        catch { finish(record, reason: .failed, reportToSystem: false); completion(error); return }
        let action = CXStartCallAction(call: record.uuid, handle: CXHandle(type: .generic, value: handle))
        action.isVideo = hasVideo
        controller.request(CXTransaction(action: action)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { completion(error); return }
                if let error = error { self.finish(record, reason: .failed, reportToSystem: false); completion(error); return }
                guard self.records[record.uuid] === record else { completion(Self.error("session_changed")); return }
                let update = CXCallUpdate()
                update.localizedCallerName = displayName
                update.hasVideo = hasVideo
                update.supportsHolding = false
                update.supportsGrouping = false
                update.supportsUngrouping = false
                update.supportsDTMF = false
                self.provider.reportCall(with: record.uuid, updated: update)
                self.scheduleExpiry(record, deadline: Date().addingTimeInterval(120))
                completion(nil)
            }
        }
    }

    func updateDisplayName(_ record: CallKitCallRecord, name: String) {
        guard records[record.uuid] === record, !name.isEmpty else { return }
        let update = CXCallUpdate()
        update.localizedCallerName = name
        provider.reportCall(with: record.uuid, updated: update)
    }

    func markAccepted(_ record: CallKitCallRecord) {
        guard records[record.uuid] === record else { return }
        record.serverAccepted = true
        record.expiry?.cancel()
        record.expiry = nil
        // The server has selected a device; media readiness is still separate.
    }

    func markConnected(_ record: CallKitCallRecord) {
        guard records[record.uuid] === record else { return }
        record.expiry?.cancel()
        record.expiry = nil
        record.status = "connected"
        if record.outgoing { provider.reportOutgoingCall(with: record.uuid, connectedAt: Date()) }
    }

    func requestAnswer(_ record: CallKitCallRecord, completion: @escaping (Bool) -> Void) {
        guard records[record.uuid] === record, !record.outgoing, record.status == "ringing" else { completion(false); return }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: record.uuid))) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func requestMute(_ record: CallKitCallRecord, muted: Bool, completion: @escaping (Bool) -> Void) {
        guard records[record.uuid] === record, record.status != "ringing" else { completion(false); return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: record.uuid, muted: muted))) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func quarantineAudio() { audio.quarantine(force: true) }

    func releaseAudioSession() -> Bool {
        guard records.isEmpty else { return false }
        audio.releaseAfterMediaStopped()
        return true
    }

    func end(_ record: CallKitCallRecord, reason: CXCallEndedReason) {
        finish(record, reason: reason)
    }

    func endAll(keepingColdCalls: Bool) {
        for record in Array(records.values) where !keepingColdCalls || !record.sessionKey.isEmpty {
            finish(record, reason: .failed)
        }
    }

    func adoptColdCalls(accountID: String, sessionKey: String) {
        for record in Array(records.values) {
            if record.accountID == accountID && record.sessionKey.isEmpty { record.sessionKey = sessionKey }
            else if record.accountID != accountID || record.sessionKey != sessionKey { finish(record, reason: .failed) }
        }
    }

    func completeAction(actionID: UUID, accountID: String, sessionKey: String, succeeded: Bool) -> Bool {
        if let completed = completedActions[actionID] {
            return completed.accountID == accountID && completed.sessionKey == sessionKey && completed.succeeded == succeeded
        }
        guard let pending = actions[actionID], pending.1.accountID == accountID,
              pending.1.sessionKey == sessionKey, records[pending.1.uuid] === pending.1 else { return false }
        actions.removeValue(forKey: actionID)
        pending.2.cancel()
        let action = pending.0, record = pending.1
        rememberAction(action, record: record, succeeded: succeeded)
        if succeeded {
            action.fulfill()
            if action is CXEndCallAction { finish(record, reason: .remoteEnded, reportToSystem: false) }
            else if action is CXAnswerCallAction { scheduleExpiry(record, deadline: Date().addingTimeInterval(30)) }
        } else {
            action.fail()
            finish(record, reason: .failed)
        }
        return true
    }

    func setAudioEnabled(_ enabled: Bool, record: CallKitCallRecord) -> Bool {
        guard records[record.uuid] === record, record.status != "ringing" else { return false }
        return audio.setEnabled(enabled)
    }

    func setSpeakerphone(_ enabled: Bool, record: CallKitCallRecord) -> Bool {
        guard records[record.uuid] === record, record.status != "ringing" else { return false }
        return audio.setSpeakerphone(enabled)
    }

    func providerDidReset(_ provider: CXProvider) {
        let previous = Array(records.values)
        previous.forEach { finish($0, reason: .failed, reportToSystem: false) }
        audio.quarantine()
        previous.forEach { onEvent?($0.event("providerReset")) }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let record = records[action.callUUID] else { action.fail(); return }
        do { try audio.prepare(hasVideo: record.hasVideo) }
        catch { action.fail(); finish(record, reason: .failed); return }
        record.status = "connecting"
        action.fulfill()
        provider.reportOutgoingCall(with: record.uuid, startedConnectingAt: Date())
        onEvent?(record.event("started"))
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let record = records[action.callUUID] else { action.fail(); return }
        do { try audio.prepare(hasVideo: record.hasVideo) }
        catch { action.fail(); finish(record, reason: .failed); return }
        record.expiry?.cancel()
        record.expiry = nil
        record.status = "connecting"
        hold(action, record: record, type: "answer")
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let record = records[action.callUUID] else { action.fulfill(); return }
        _ = audio.setEnabled(false)
        hold(action, record: record, type: "end")
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let record = records[action.callUUID] else { action.fail(); return }
        hold(action, record: record, type: "mute", extra: ["muted": action.isMuted])
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        guard let pending = actions.removeValue(forKey: action.uuid) else { return }
        pending.2.cancel()
        rememberAction(action, record: pending.1, succeeded: false)
        var event = pending.1.event("actionTimedOut")
        event["actionID"] = action.uuid.uuidString
        onEvent?(event)
        finish(pending.1, reason: .failed)
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        guard let record = records.values.first else { return }
        audio.didActivate(audioSession)
        onEvent?(record.event("audioActivated"))
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        audio.didDeactivate(audioSession)
        if let record = records.values.first { onEvent?(record.event("audioDeactivated")) }
    }

    private func hold(_ action: CXAction, record: CallKitCallRecord, type: String, extra: [String: Any] = [:]) {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, let pending = self.actions.removeValue(forKey: action.uuid) else { return }
            pending.0.fail()
            self.rememberAction(pending.0, record: record, succeeded: false)
            var event = record.event("actionTimedOut")
            event["actionID"] = action.uuid.uuidString
            self.onEvent?(event)
            self.finish(record, reason: .failed)
        }
        actions[action.uuid] = (action, record, timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        var event = record.event(type)
        event["actionID"] = action.uuid.uuidString
        extra.forEach { event[$0.key] = $0.value }
        onEvent?(event)
    }

    private func scheduleExpiry(_ record: CallKitCallRecord, deadline: Date) {
        record.expiry?.cancel()
        record.expiry = nil
        guard !record.serverAccepted else { return }
        let expiry = DispatchWorkItem { [weak self] in
            guard let self = self, self.records[record.uuid] === record,
                  !record.serverAccepted, record.status != "connected" else { return }
            var event = record.event("expired")
            event["status"] = record.status
            self.onEvent?(event)
            self.finish(record, reason: record.status == "connecting" ? .failed : .unanswered)
        }
        record.expiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: expiry)
    }

    private func finish(_ record: CallKitCallRecord, reason: CXCallEndedReason, reportToSystem: Bool = true) {
        guard records[record.uuid] === record else { return }
        record.expiry?.cancel()
        record.expiry = nil
        for (id, pending) in Array(actions) where pending.1 === record {
            pending.2.cancel()
            let endAction = pending.0 is CXEndCallAction
            if endAction { pending.0.fulfill() } else { pending.0.fail() }
            rememberAction(pending.0, record: record, succeeded: endAction)
            actions.removeValue(forKey: id)
        }
        records.removeValue(forKey: record.uuid)
        endedRooms[record.accountID + "\n" + record.roomID] = Date()
        if endedRooms.count > 128, let oldest = endedRooms.min(by: { $0.value < $1.value }) { endedRooms.removeValue(forKey: oldest.key) }
        if reportToSystem { provider.reportCall(with: record.uuid, endedAt: Date(), reason: reason) }
        if records.isEmpty { audio.quarantine() }
        onRecordEnded?(record)
        onEvent?(record.event("ended"))
    }

    private func rememberAction(_ action: CXAction, record: CallKitCallRecord, succeeded: Bool) {
        completedActions[action.uuid] = (record.accountID, record.sessionKey, succeeded)
        completedActionOrder.append(action.uuid)
        if completedActionOrder.count > 128 { completedActions.removeValue(forKey: completedActionOrder.removeFirst()) }
    }

    private static func error(_ code: String) -> NSError { return NSError(domain: "IOSVoIPCallKit", code: 1, userInfo: ["reason": code]) }
}
