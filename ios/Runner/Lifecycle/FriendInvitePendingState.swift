import Foundation

/// Queue semantics are independent of Flutter and the scene's arrival order.
struct FriendInvitePendingState {
    struct Invite {
        let sequence: UInt64
        let value: String
    }

    private var sequence: UInt64 = 0
    private var pending: Invite?

    mutating func receive(_ url: URL) -> Invite? {
        guard ["chat99", "openim"].contains(url.scheme?.lowercased() ?? ""),
              url.host == "user" else { return nil }
        sequence &+= 1
        let invite = Invite(sequence: sequence, value: url.absoluteString)
        pending = invite
        return invite
    }

    mutating func take() -> String? {
        defer { pending = nil }
        return pending?.value
    }

    mutating func acknowledge(_ invite: Invite) {
        if pending?.sequence == invite.sequence { pending = nil }
    }
}
