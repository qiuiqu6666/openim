package io.openim.calling;

/** Standalone JVM checks; no emulator, real call or backend connection. */
public final class CallPipExitPolicyTest {
    private static void expect(CallPipExitPolicy.Exit expected, boolean resumed,
                               boolean pip, boolean interactive, boolean locked) {
        CallPipExitPolicy.Exit actual =
                CallPipExitPolicy.decide(resumed, pip, interactive, locked);
        if (actual != expected) throw new AssertionError(expected + " != " + actual);
    }

    private static void expectRestore(boolean expected, boolean programmatic,
                                      boolean active, boolean pip) {
        boolean actual = CallPipExitPolicy.restoreAfterStop(programmatic, active, pip);
        if (actual != expected) throw new AssertionError(expected + " != " + actual);
    }

    private static void expectEntryTimeout(boolean expected, boolean enabled,
                                           boolean entering, boolean pip) {
        boolean actual = CallPipExitPolicy.entryTimedOut(enabled, entering, pip);
        if (actual != expected) throw new AssertionError(expected + " != " + actual);
    }

    public static void main(String[] args) {
        expect(CallPipExitPolicy.Exit.RESTORED, true, false, true, false);
        expect(CallPipExitPolicy.Exit.CLOSED, false, false, true, false);
        expect(CallPipExitPolicy.Exit.CLOSED, false, true, true, false);
        expect(CallPipExitPolicy.Exit.NONE, false, true, false, false);
        expect(CallPipExitPolicy.Exit.NONE, false, true, true, true);
        expect(CallPipExitPolicy.Exit.NONE, true, true, true, false);
        expectRestore(true, true, true, true);
        expectRestore(false, false, true, true); // User X must not reopen the app.
        expectRestore(false, true, false, true); // No active native call window.
        expectRestore(false, true, true, false); // Already restored by the system.
        expectEntryTimeout(true, true, true, false);
        expectEntryTimeout(false, true, true, true); // A real window is active.
        expectEntryTimeout(false, false, true, false); // A stopped call.
        expectEntryTimeout(false, true, false, false); // An already failed entry.
        System.out.println("Call PiP lifecycle policy: 14 checks passed");
    }
}
