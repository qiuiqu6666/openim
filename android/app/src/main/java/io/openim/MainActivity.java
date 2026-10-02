package io.openim;

import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {
    private static final String SYSTEM_SHARE_CHANNEL = "openim_system_share";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                SYSTEM_SHARE_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if (!"shareText".equals(call.method)) {
                result.notImplemented();
                return;
            }

            String text = call.argument("text");
            if (text == null || text.trim().isEmpty()) {
                result.success(false);
                return;
            }

            try {
                Intent sendIntent = new Intent(Intent.ACTION_SEND);
                sendIntent.setType("text/plain");
                sendIntent.putExtra(Intent.EXTRA_TEXT, text.trim());

                Intent chooser = Intent.createChooser(sendIntent, "更多分享");
                excludeBluetoothShareTargets(sendIntent, chooser);
                startActivity(chooser);
                result.success(true);
            } catch (Exception ignored) {
                result.success(false);
            }
        });
    }

    private void excludeBluetoothShareTargets(Intent sendIntent, Intent chooser) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return;
        }

        ArrayList<ComponentName> excluded = new ArrayList<>();

        // AOSP Bluetooth OPP share target used by many Android builds.
        excluded.add(new ComponentName(
                "com.android.bluetooth",
                "com.android.bluetooth.opp.BluetoothOppLauncherActivity"
        ));

        try {
            PackageManager packageManager = getPackageManager();
            List<ResolveInfo> targets = packageManager.queryIntentActivities(
                    sendIntent,
                    PackageManager.MATCH_DEFAULT_ONLY
            );
            for (ResolveInfo info : targets) {
                if (info.activityInfo == null) continue;
                String packageName = info.activityInfo.packageName == null
                        ? "" : info.activityInfo.packageName;
                String className = info.activityInfo.name == null
                        ? "" : info.activityInfo.name;
                String normalized = (packageName + "/" + className)
                        .toLowerCase(Locale.ROOT);
                if (normalized.contains("bluetooth")) {
                    ComponentName component = new ComponentName(packageName, className);
                    if (!excluded.contains(component)) {
                        excluded.add(component);
                    }
                }
            }
        } catch (Exception ignored) {
            // The explicit AOSP component above still covers the common case.
        }

        chooser.putExtra(
                Intent.EXTRA_EXCLUDE_COMPONENTS,
                excluded.toArray(new ComponentName[0])
        );
    }
}
