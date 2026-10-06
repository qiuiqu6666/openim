package io.openim.calling;

import android.app.Activity;
import android.app.AppOpsManager;
import android.app.KeyguardManager;
import android.app.PictureInPictureParams;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Rational;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** Activity PiP belongs to the active call, never to a group live cast. */
public final class CallPictureInPictureBridge {
    private final Activity activity;
    private final MethodChannel channel;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private String session;
    private boolean enabled;
    private boolean active;
    private boolean entering;
    private boolean resumed;
    private boolean disposed;
    private int width = 9;
    private int height = 16;
    private Rect sourceRect;
    private Runnable pendingExit;
    private Runnable pendingEntry;

    public CallPictureInPictureBridge(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, "openim_call_pip");
        channel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "configure": {
                    Boolean requested = call.argument("enabled");
                    String requestedSession = call.argument("session");
                    if (!Boolean.TRUE.equals(requested) || requestedSession == null) {
                        stop(true);
                        result.success(capability(false));
                        return;
                    }
                    if (!requestedSession.equals(session)) {
                        cancelPendingExit();
                        cancelPendingEntry();
                        entering = false;
                    }
                    session = requestedSession;
                    enabled = supported();
                    Number requestedWidth = call.argument("aspectWidth");
                    Number requestedHeight = call.argument("aspectHeight");
                    width = requestedWidth == null ? 9 : requestedWidth.intValue();
                    height = requestedHeight == null ? 16 : requestedHeight.intValue();
                    Map<String, Number> rect = call.argument("sourceRect");
                    sourceRect = readRect(rect);
                    boolean ready = enabled && updateParams();
                    result.success(capability(ready));
                    return;
                }
                case "enter":
                    result.success(matches(call.argument("session")) && enter());
                    return;
                case "stop":
                    if (matches(call.argument("session"))) stop(true);
                    result.success(true);
                    return;
                default:
                    result.notImplemented();
            }
        });
    }

    private boolean matches(String requested) {
        return !disposed && session != null && session.equals(requested);
    }

    private boolean supported() {
        return capable() && permitted();
    }

    private boolean capable() {
        return !disposed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !activity.isFinishing() && !activity.isDestroyed()
                && activity.getPackageManager().hasSystemFeature(
                        PackageManager.FEATURE_PICTURE_IN_PICTURE);
    }

    private boolean permitted() {
        AppOpsManager ops = (AppOpsManager) activity.getSystemService(Context.APP_OPS_SERVICE);
        if (ops == null) return false;
        try {
            int mode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    ? ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                            activity.getApplicationInfo().uid, activity.getPackageName())
                    : ops.checkOpNoThrow(AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                            activity.getApplicationInfo().uid, activity.getPackageName());
            // PiP is declared by this Activity; a default app-op uses that
            // manifest check. An explicitly disabled app-op is unsupported.
            return mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT;
        } catch (SecurityException | IllegalArgumentException ignored) {
            return false;
        }
    }

    private Map<String, Object> capability(boolean ready) {
        Map<String, Object> value = new HashMap<>();
        value.put("supported", supported());
        value.put("ready", ready);
        value.put("backgroundCameraSupported", supported());
        return value;
    }

    private PictureInPictureParams params() {
        double ratio = height > 0 ? (double) width / height : 0;
        if (width <= 0 || height <= 0 || ratio < 0.42 || ratio > 2.39) {
            width = 9;
            height = 16;
        }
        PictureInPictureParams.Builder builder = new PictureInPictureParams.Builder()
                .setAspectRatio(new Rational(width, height));
        if (sourceRect != null && !sourceRect.isEmpty()) {
            builder.setSourceRectHint(sourceRect);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(enabled);
            builder.setSeamlessResizeEnabled(false);
        }
        return builder.build();
    }

    private boolean updateParams() {
        // Disarming params must still work after the user revokes PiP access.
        if (!capable()) return false;
        try {
            activity.setPictureInPictureParams(params());
            return true;
        } catch (IllegalArgumentException | IllegalStateException | SecurityException ignored) {
            return false;
        }
    }

    public boolean enter() {
        if (!enabled || !supported()) return false;
        if (activity.isInPictureInPictureMode()) return true;
        if (entering) return false;
        entering = true;
        watchEntry();
        emit("entering");
        try {
            boolean accepted = activity.enterPictureInPictureMode(params());
            if (!accepted) failed();
            return accepted;
        } catch (IllegalArgumentException | IllegalStateException | SecurityException ignored) {
            failed();
            return false;
        }
    }

    public void onUserLeaveHint() {
        // Android 12+ performs automatic entry from its configured params.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enter();
        } else if (enabled) {
            entering = true;
            watchEntry();
            emit("entering");
        }
    }

    public void onModeChanged(boolean inPip) {
        if (!enabled) return;
        cancelPendingExit();
        cancelPendingEntry();
        if (inPip) {
            active = true;
            entering = false;
            emit("active");
        } else if (active) {
            scheduleExit();
        } else if (entering) {
            failed();
        }
    }

    public void onResume() {
        resumed = true;
        if (active && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !activity.isInPictureInPictureMode()) restored();
    }

    public void onPause() { resumed = false; }

    public void onStop() {
        // Merely requesting auto-entry does not prove a PiP window existed.
        // User-disabled PiP can background the Activity without a mode callback.
        if (active) scheduleExit();
    }

    private void scheduleExit() {
        cancelPendingExit();
        final String exitingSession = session;
        pendingExit = () -> {
            pendingExit = null;
            if (!enabled || !matches(exitingSession)) return;
            // Screen-off/keyguard is not a user dismissal. An ordinary PiP
            // remains visible while paused; onStop with an interactive,
            // unlocked display means the user removed that window.
            PowerManager power = (PowerManager) activity.getSystemService(Context.POWER_SERVICE);
            KeyguardManager keyguard = (KeyguardManager) activity.getSystemService(Context.KEYGUARD_SERVICE);
            CallPipExitPolicy.Exit exit = CallPipExitPolicy.decide(
                    resumed, activity.isInPictureInPictureMode(),
                    power != null && power.isInteractive(),
                    keyguard != null && keyguard.isKeyguardLocked());
            if (exit == CallPipExitPolicy.Exit.RESTORED) restored();
            if (exit == CallPipExitPolicy.Exit.CLOSED) closed();
        };
        handler.postDelayed(pendingExit, 350);
    }

    private void restored() {
        cancelPendingExit();
        cancelPendingEntry();
        active = false;
        entering = false;
        emit("restored");
    }

    private void closed() {
        emit("closed");
        stop(false);
    }

    private void failed() {
        cancelPendingEntry();
        entering = false;
        emit("failed");
    }

    private void watchEntry() {
        cancelPendingEntry();
        final String enteringSession = session;
        pendingEntry = () -> {
            pendingEntry = null;
            if (!enabled || !matches(enteringSession) || !entering) return;
            boolean inPip = activity.isInPictureInPictureMode();
            if (CallPipExitPolicy.entryTimedOut(enabled, entering, inPip)) {
                failed();
            } else if (inPip) {
                // Recover a delayed/missing mode callback from actual OS state.
                onModeChanged(true);
            }
        };
        handler.postDelayed(pendingEntry, 3000);
    }

    private void emit(String phase) {
        if (disposed || session == null) return;
        Map<String, Object> value = new HashMap<>();
        value.put("session", session);
        value.put("phase", phase);
        channel.invokeMethod("state", value);
    }

    private void stop(boolean restoreActivity) {
        boolean shouldRestore = capable() && CallPipExitPolicy.restoreAfterStop(
                restoreActivity, active, activity.isInPictureInPictureMode());
        cancelPendingExit();
        cancelPendingEntry();
        enabled = false;
        active = false;
        entering = false;
        session = null;
        updateParams(); // Disarm automatic entry before the next home gesture.
        if (shouldRestore) {
            // Android has no public Activity.stopPictureInPicture API. Keep
            // the existing Flutter engine/session and expand this Activity
            // instead of leaving unrelated chat UI inside an ended call's PiP.
            try {
                Intent intent = new Intent(activity, activity.getClass());
                intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                        | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                activity.startActivity(intent);
            } catch (IllegalStateException | SecurityException ignored) {
                // Auto-entry is still disarmed if the system refuses restore.
            }
        }
    }

    private void cancelPendingExit() {
        if (pendingExit != null) handler.removeCallbacks(pendingExit);
        pendingExit = null;
    }

    private void cancelPendingEntry() {
        if (pendingEntry != null) handler.removeCallbacks(pendingEntry);
        pendingEntry = null;
    }

    private static Rect readRect(Map<String, Number> value) {
        if (value == null) return null;
        for (String key : new String[]{"left", "top", "right", "bottom"}) {
            Number number = value.get(key);
            if (number == null || !Double.isFinite(number.doubleValue())) return null;
        }
        return new Rect(value.get("left").intValue(), value.get("top").intValue(),
                value.get("right").intValue(), value.get("bottom").intValue());
    }

    public void dispose() {
        if (disposed) return;
        if (enabled && active && activity.isFinishing()) emit("closed");
        stop(false);
        disposed = true;
        channel.setMethodCallHandler(null);
    }
}
