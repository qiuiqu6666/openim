/// Main-queue policy. A snapshot or repeated notification is not a handover.
/// Keep the pre-background path until resume so a real handover is handled once.
struct IMNetworkPathPolicy {
    private var lastPath: String?
    private var lastWakePath: String?
    private var lastWakeTime: Double?

    mutating func reset(path: String? = nil) {
        lastPath = path
        lastWakePath = nil
        lastWakeTime = nil
    }

    mutating func observe(path: String, online: Bool, foreground: Bool) -> Bool {
        guard foreground else { return false }
        let previous = lastPath
        lastPath = path
        return online && previous != nil && previous != path
    }

    /// Dart recovery and Reachability can report the same handover together.
    /// Share a short monotonic guard so the second signal cannot close the
    /// socket that the first signal just reconnected. A new path is immediate.
    mutating func allowWake(path: String, now: Double) -> Bool {
        if lastWakePath == path, let last = lastWakeTime, now - last < 1 {
            return false
        }
        lastWakePath = path
        lastWakeTime = now
        return true
    }
}
