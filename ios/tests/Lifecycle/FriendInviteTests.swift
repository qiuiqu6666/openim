import Foundation

@main
struct FriendInviteTests {
    static func main() {
        var state = FriendInvitePendingState()
        let first = URL(string: "chat99://user?id=first")!
        let second = URL(string: "openim://user?id=second")!
        // A cold URL arriving before Flutter is consumed exactly once.
        precondition(state.receive(first) != nil)
        precondition(state.take() == first.absoluteString)
        precondition(state.take() == nil)
        // Unknown URLs are forwarded to other handlers and cannot erase an invite.
        let initial = state.receive(first)!
        precondition(state.receive(URL(string: "https://example.com/user")!) == nil)
        precondition(state.receive(URL(string: "chat99://other?id=no")!) == nil)
        precondition(state.take() == first.absoluteString)
        // Warm delivery acknowledgment removes only the matching pending event.
        let warm = state.receive(second)!
        state.acknowledge(warm)
        precondition(state.take() == nil)
        // An old asynchronous acknowledgment must not erase a newer invitation.
        let newer = state.receive(second)!
        state.acknowledge(initial)
        precondition(state.take() == second.absoluteString)
        // Repeated taps on the same URL are still distinct deliveries.
        _ = state.receive(second)
        state.acknowledge(newer)
        precondition(state.take() == second.absoluteString)
        print("Friend invitation cold/warm queue tests passed")
    }
}
