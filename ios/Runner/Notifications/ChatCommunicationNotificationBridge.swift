import Flutter
import ImageIO
import Intents
import UIKit
import UserNotifications

/// Adds communication avatars to local chat notifications. Response delivery
/// remains with flutter_local_notifications and FlutterAppDelegate.
final class ChatCommunicationNotificationBridge {
    private let channel: FlutterMethodChannel
    private let center = UNUserNotificationCenter.current()
    private let images = DispatchQueue(label: "openim.chat.notification.images", qos: .utility)
    private var sessionKey: String?
    private var generation = 0
    private var pending: [String: Request] = [:]
    // Keep a submitted request until UNUserNotificationCenter's completion,
    // even when our Flutter deadline already replied. A click/session change
    // must still be able to invalidate that in-flight delivery.
    private var deliveries: [String: Request] = [:]

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "openim_chat_notifications", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(true); return }
            self.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "setSession":
            guard let key = args["sessionKey"] as? String, !key.isEmpty else {
                result(FlutterError(code: "INVALID_SESSION", message: "sessionKey is required", details: nil))
                return
            }
            if key != sessionKey {
                invalidateSession()
                sessionKey = key
            }
            result(true)
        case "clearSession":
            if let expected = args["sessionKey"] as? String, expected != sessionKey {
                result(true)
                return
            }
            invalidateSession()
            result(true)
        case "invalidateNotification":
            guard args["sessionKey"] as? String == sessionKey,
                  let id = args["id"] as? NSNumber else { result(true); return }
            if let request = pending[id.stringValue] {
                finish(request, handled: true, discarded: true)
            }
            if let request = deliveries[id.stringValue] {
                finish(request, handled: true, discarded: true)
            }
            result(true)
        case "showCommunicationNotification":
            guard let notification = Notification(args) else {
                result(FlutterError(code: "INVALID_NOTIFICATION", message: "Required chat fields are missing", details: nil))
                return
            }
            guard notification.sessionKey == sessionKey else { result(true); return }
            let request = Request(notification, generation: generation, result: result)
            if let previous = pending[request.id] {
                finish(previous, handled: true, discarded: true)
            }
            if let previous = deliveries[request.id] {
                finish(previous, handled: true, discarded: true)
            }
            // A valid incoming group has at least sender + current recipient.
            // Unknown/stale counts cannot describe group participants reliably.
            if notification.isGroup && (notification.groupMemberCount ?? 0) < 2 {
                result(false)
                return
            }
            pending[request.id] = request
            let deadline = DispatchWorkItem { [weak self, weak request] in
                guard let self = self, let request = request, !request.completed else { return }
                // Once submitted, a delayed add callback must not trigger a
                // duplicate fallback. Late donation work never gets submitted.
                self.finish(request, handled: request.deliveryStarted || !self.isCurrent(request))
            }
            request.deadline = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: deadline)
            images.async { [weak self] in
                let group = notification.isGroup ? Self.avatarData(notification.conversationAvatarPath) : nil
                // Dart may only have the group avatar. Do not attribute that
                // same bitmap to the individual sender or decode it twice.
                let sender = notification.isGroup &&
                    notification.senderAvatarPath == notification.conversationAvatarPath
                    ? nil : Self.avatarData(notification.senderAvatarPath)
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrent(request) else { return }
                    guard (notification.isGroup ? group != nil : sender != nil) else {
                        self.finish(request, handled: false)
                        return
                    }
                    self.donate(request, senderImage: sender, groupImage: group)
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func isCurrent(_ request: Request) -> Bool {
        !request.completed && request.generation == generation &&
            request.notification.sessionKey == sessionKey && pending[request.id] === request
    }

    private func invalidateSession() {
        if let previous = sessionKey {
            // Delete only this notification module's old scope. A late old
            // donation is removed again by its completion, using its own ID.
            INInteraction.delete(with: "openim.chat:\(previous)", completion: nil)
        }
        generation += 1
        sessionKey = nil
        for request in Array(pending.values) {
            finish(request, handled: true, discarded: true)
        }
        for request in Array(deliveries.values) {
            finish(request, handled: true, discarded: true)
        }
    }

    private func finish(_ request: Request, handled: Bool, discarded: Bool = false) {
        if discarded {
            request.discarded = true
            if request.deliveryStarted { removeLateDelivery(request) }
        }
        guard !request.completed else { return }
        request.completed = true
        request.deadline?.cancel()
        request.deadline = nil
        if pending[request.id] === request { pending.removeValue(forKey: request.id) }
        request.result(handled)
    }

    private func removeLateDelivery(_ request: Request) {
        // Native updates and ordinary FLN fallback both reuse this ID. Check
        // the actual content ticket before removing a late old submission.
        guard deliveries[request.id] === request else { return }
        center.getPendingNotificationRequests { [weak self] notifications in
            DispatchQueue.main.async {
                guard let self = self,
                      notifications.contains(where: { self.isDelivery($0, request: request) }) else { return }
                self.center.removePendingNotificationRequests(withIdentifiers: [request.id])
            }
        }
        center.getDeliveredNotifications { [weak self] notifications in
            DispatchQueue.main.async {
                guard let self = self,
                      notifications.contains(where: { self.isDelivery($0.request, request: request) }) else { return }
                self.center.removeDeliveredNotifications(withIdentifiers: [request.id])
            }
        }
    }

    private func isDelivery(_ notification: UNNotificationRequest, request: Request) -> Bool {
        // A newer native request supersedes the ticket even if the old OS query
        // began first. Ordinary FLN notices lack our private ticket entirely.
        if let owner = deliveries[request.id], owner !== request { return false }
        return notification.identifier == request.id &&
            (notification.content.userInfo["openimChatDeliveryTicket"] as? String) == request.ticket.uuidString
    }

    private func donate(_ request: Request, senderImage: Data?, groupImage: Data?) {
        let data = request.notification
        let sender = INPerson(
            personHandle: INPersonHandle(value: data.senderID, type: .unknown),
            nameComponents: nil,
            displayName: data.senderName,
            image: senderImage.map { INImage(imageData: $0) },
            contactIdentifier: nil,
            customIdentifier: "\(data.sessionKey):\(data.senderID)",
            isMe: false)
        // The system supplies the current user for incoming communication
        // donations. Do not donate the current account as another participant.
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: data.body,
            speakableGroupName: data.isGroup ? INSpeakableString(spokenPhrase: data.title) : nil,
            conversationIdentifier: "\(data.sessionKey):\(data.conversationID)",
            serviceName: nil,
            sender: sender,
            attachments: nil)
        if let group = groupImage {
            intent.setImage(INImage(imageData: group), forParameterNamed: \.speakableGroupName)
        }
        if data.isGroup, let members = data.groupMemberCount {
            let metadata = INSendMessageIntentDonationMetadata()
            // Sender is not a recipient; the incoming current user is included
            // in the full count without donating an extra current-user person.
            metadata.recipientCount = members - 1
            intent.donationMetadata = metadata
        }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.identifier = "openim.chat:\(data.sessionKey):\(request.ticket.uuidString)"
        interaction.groupIdentifier = "openim.chat:\(data.sessionKey)"
        interaction.direction = .incoming
        interaction.donate { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.isCurrent(request) else {
                    INInteraction.delete(with: [interaction.identifier], completion: nil)
                    return
                }
                guard error == nil else { self.finish(request, handled: false); return }
                let original = data.content()
                do {
                    guard let updated = try original.updating(from: intent).mutableCopy()
                        as? UNMutableNotificationContent else {
                        self.finish(request, handled: false)
                        return
                    }
                    // Retain response/category, per-conversation grouping and
                    // alert choices; updating(from:) may replace these fields.
                    updated.title = original.title
                    updated.body = original.body
                    updated.categoryIdentifier = original.categoryIdentifier
                    updated.threadIdentifier = original.threadIdentifier
                    updated.userInfo = original.userInfo
                    updated.sound = original.sound
                    updated.interruptionLevel = original.interruptionLevel
                    self.add(updated, request: request)
                } catch {
                    self.finish(request, handled: false)
                }
            }
        }
    }

    private func add(_ content: UNMutableNotificationContent, request: Request) {
        guard isCurrent(request) else { return }
        request.deliveryStarted = true
        deliveries[request.id] = request
        content.userInfo["openimChatDeliveryTicket"] = request.ticket.uuidString
        center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: nil)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let inactive = request.discarded || request.generation != self.generation ||
                    request.notification.sessionKey != self.sessionKey
                if inactive { self.removeLateDelivery(request) }
                if self.deliveries[request.id] === request {
                    self.deliveries.removeValue(forKey: request.id)
                }
                if !request.completed { self.finish(request, handled: inactive || error == nil) }
            }
        }
    }

    /// Only local cache files are accepted. Decode/resize off the UI thread and
    /// bound both encoded size and the eventual notification bitmap.
    private static func avatarData(_ path: String?) -> Data? {
        guard let path = path, path.hasPrefix("/"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 2 * 1024 * 1024,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    private final class Request {
        let notification: Notification
        let generation: Int
        let result: FlutterResult
        let ticket = UUID()
        var id: String { String(notification.id) }
        var deadline: DispatchWorkItem?
        var completed = false
        var discarded = false
        var deliveryStarted = false

        init(_ notification: Notification, generation: Int, result: @escaping FlutterResult) {
            self.notification = notification
            self.generation = generation
            self.result = result
        }
    }

    private struct Notification {
        let id: Int
        let sessionKey: String
        let conversationID: String
        let title: String
        let body: String
        let payload: String
        let categoryIdentifier: String
        let senderID: String
        let senderName: String
        let isGroup: Bool
        let groupMemberCount: Int?
        let senderAvatarPath: String?
        let conversationAvatarPath: String?
        let alert: Bool
        let presentBanner: Bool
        let presentList: Bool
        let presentSound: Bool
        let playSound: Bool
        let soundName: String?

        init?(_ args: [String: Any]) {
            guard let id = args["id"] as? NSNumber, id.int64Value >= 0, id.int64Value <= Int64(Int32.max),
                  let sessionKey = args["sessionKey"] as? String, !sessionKey.isEmpty,
                  let conversationID = args["conversationID"] as? String, !conversationID.isEmpty,
                  let title = args["title"] as? String,
                  let body = args["body"] as? String,
                  let payload = args["payload"] as? String,
                  let category = args["categoryIdentifier"] as? String,
                  let senderID = args["senderID"] as? String, !senderID.isEmpty,
                  let senderName = args["senderName"] as? String else { return nil }
            self.id = id.intValue
            self.sessionKey = sessionKey
            self.conversationID = conversationID
            self.title = title
            self.body = body
            self.payload = payload
            categoryIdentifier = category
            self.senderID = senderID
            self.senderName = senderName
            isGroup = args["isGroup"] as? Bool ?? false
            groupMemberCount = (args["groupMemberCount"] as? NSNumber)?.intValue
            senderAvatarPath = args["senderAvatarPath"] as? String
            conversationAvatarPath = args["conversationAvatarPath"] as? String
            alert = args["alert"] as? Bool ?? true
            presentBanner = alert && (args["presentBanner"] as? Bool ?? true)
            presentList = args["presentList"] as? Bool ?? true
            presentSound = alert && (args["presentSound"] as? Bool ?? true)
            playSound = alert && (args["playSound"] as? Bool ?? true)
            let allowedSounds = Set(["preview000", "crisp", "soft", "chime", "preview", "preview1", "preview04"]
                .map { "chat_message_\($0).wav" })
            let requestedSound = args["soundName"] as? String
            soundName = requestedSound.flatMap { allowedSounds.contains($0) ? $0 : nil }
        }

        func content() -> UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = categoryIdentifier
            content.threadIdentifier = "\(sessionKey):\(conversationID)"
            content.sound = playSound
                ? soundName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
                : nil
            content.interruptionLevel = alert ? .active : .passive
            // Pinned to flutter_local_notifications 18.0.1's iOS contract:
            // isAFlutterLocalNotification / buildUserDict / response extraction.
            content.userInfo = [
                "NotificationId": id, "payload": payload, "title": title,
                "presentAlert": alert, "presentBadge": false,
                "presentSound": presentSound, "presentBanner": presentBanner,
                "presentList": presentList
            ]
            return content
        }
    }
}
