package io.openim.live;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.provider.Settings;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** Opens a real system cast surface without sharing the live stream URL. */
public final class LiveCastBridge {
    private final MethodChannel channel;

    public LiveCastBridge(Activity activity, BinaryMessenger messenger) {
        channel = new MethodChannel(messenger, "openim_group_live_cast");
        channel.setMethodCallHandler((call, result) -> {
            if (!"openCastSettings".equals(call.method)) {
                result.notImplemented();
                return;
            }
            if (activity.isFinishing() || activity.isDestroyed()) {
                result.success(false);
                return;
            }
            // Some vendor builds expose the Wi-Fi display action instead.
            String[] actions = {
                    Settings.ACTION_CAST_SETTINGS,
                    "android.settings.WIFI_DISPLAY_SETTINGS"
            };
            for (String action : actions) {
                try {
                    activity.startActivity(new Intent(action));
                    result.success(true);
                    return;
                } catch (ActivityNotFoundException | SecurityException ignored) {
                    // A missing/non-exported activity is not a successful cast.
                }
            }
            result.success(false);
        });
    }

    public void dispose() {
        channel.setMethodCallHandler(null);
    }
}
