import Foundation
import CoreFoundation

/// The native report must not wait for Flutter. Business validation still uses
/// the same complete OpenIM invitation when the authenticated SDK is ready.
struct VoIPCallPayload {
    let raw: [String: Any]
    let roomID: String
    let accountID: String
    let callerID: String
    let callerName: String
    let hasVideo: Bool
    let deadline: Date?
    let valid: Bool

    init(_ input: [String: Any]) {
        let payload = Self.payload(input) ?? [:]
        accountID = Self.string(payload, ["recipientUserID", "accountID", "calleeId", "calleeID"])
        let invitation: [String: Any]
        if payload["invitation"] != nil {
            invitation = Self.map(payload["invitation"]) ?? [:]
        } else {
            // Legacy aliases are normalized once so Flutter receives the same
            // canonical invitation that was checked before the native report.
            var legacy: [String: Any] = [
                "roomID": Self.string(payload, ["roomID", "roomId", "callId", "callID"]),
                "inviterUserID": Self.string(payload, ["inviterUserID", "callerId", "callerID"]),
                "inviteeUserIDList": payload["inviteeUserIDList"] ?? [accountID],
                "mediaType": payload["mediaType"] ?? NSNull(),
                "sessionType": payload["sessionType"] ?? 1,
                "initiateTime": payload["initiateTime"] ?? payload["sentAtMs"] ?? NSNull(),
                "timeout": payload["timeout"] ?? payload["timeoutSec"] ?? NSNull()
            ]
            legacy["groupID"] = payload["groupID"] ?? payload["groupId"]
            legacy["platformID"] = payload["platformID"]
            invitation = legacy
        }
        roomID = Self.string(invitation, ["roomID"])
        callerID = Self.string(invitation, ["inviterUserID"])
        let name = Self.string(payload, ["callerName", "displayName"])
        callerName = name.isEmpty ? "99chat" : name
        let media = Self.string(invitation, ["mediaType"])
        hasVideo = media == "video"
        let invitees = invitation["inviteeUserIDList"] as? [String]
        let sessionType = Self.integer(invitation["sessionType"])
        let time = Self.integer(invitation["initiateTime"])
        let timeout = Self.integer(invitation["timeout"])
        if let time = time, time > 0, let timeout = timeout, timeout > 0, timeout <= 120 {
            let milliseconds = time < 100_000_000_000 ? time * 1000 : time
            let origin = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
            deadline = origin.timeIntervalSinceNow <= 5
                ? origin.addingTimeInterval(Double(timeout)) : nil
        } else {
            // Arrival time cannot extend an invitation with a missing origin.
            deadline = nil
        }
        let group = invitation["groupID"]
        let single = group == nil || group is NSNull || group as? String == ""
        let action = payload["action"]
        let callEnd = payload["call_end"] as? NSNumber
        let terminalFlag = callEnd.map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
        let terminal = terminalFlag || Self.integer(payload["call_end"]) == 1
            || (action != nil && !(action is NSNull) && action as? String != "invite")
        valid = roomID.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil
            && !accountID.isEmpty && !callerID.isEmpty && !terminal && single
            && callerID != accountID && (media == "audio" || media == "video")
            && sessionType == 1 && invitees == [accountID] && deadline != nil
        var canonical = payload
        canonical["recipientUserID"] = accountID
        canonical["invitation"] = invitation
        canonical["callerName"] = callerName
        raw = Self.codecMap(canonical)
    }

    static func string(_ map: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let value = map[key] as? String, !value.isEmpty,
               value == value.trimmingCharacters(in: .whitespacesAndNewlines) {
                return value
            }
        }
        return ""
    }

    static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  number.doubleValue >= Double(Int.min), number.doubleValue < Double(Int.max) else { return nil }
            return number.intValue
        }
        if let value = value as? Int { return value }
        return nil
    }

    private static func payload(_ input: [String: Any]) -> [String: Any]? {
        var result: [String: Any]? = input
        // Match Flutter's bounded data-envelope traversal, including JSON data.
        for _ in 0..<4 {
            guard let current = result else { return nil }
            guard let data = current["data"] else { return current }
            result = map(data)
        }
        return nil
    }

    private static func map(_ value: Any?) -> [String: Any]? {
        if let text = value as? String, let data = text.data(using: .utf8) {
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return value as? [String: Any]
    }

    static func codecMap(_ input: [String: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for (key, value) in input {
            if let safe = codecValue(value) { output[key] = safe }
        }
        return output
    }

    private static func codecValue(_ value: Any) -> Any? {
        if let map = value as? [String: Any] { return codecMap(map) }
        if let array = value as? [Any] { return array.compactMap(codecValue) }
        return value is String || value is NSNumber || value is NSNull ? value : nil
    }
}
