package io.openim.calling;

/** A locked or screen-off phone is not a dismissed call. */
public final class CallPipExitPolicy {
    public enum Exit { NONE, RESTORED, CLOSED }

    private CallPipExitPolicy() {}

    public static boolean restoreAfterStop(boolean programmatic, boolean active, boolean inPip) {
        return programmatic && active && inPip;
    }

    public static boolean entryTimedOut(boolean enabled, boolean entering, boolean inPip) {
        return enabled && entering && !inPip;
    }

    public static Exit decide(boolean resumed, boolean inPip,
                              boolean interactive, boolean locked) {
        if (resumed && !inPip) return Exit.RESTORED;
        if (!resumed && interactive && !locked) return Exit.CLOSED;
        return Exit.NONE;
    }
}
