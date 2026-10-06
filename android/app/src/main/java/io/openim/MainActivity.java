package io.openim;

import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.res.Configuration;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.openim.live.LiveCastBridge;
import io.openim.calling.CallPictureInPictureBridge;
import io.openim.location.NativeChatLocationMapFactory;

public class MainActivity extends FlutterFragmentActivity {
    private MethodChannel inviteChannel;
    private LiveCastBridge liveCastBridge;
    private CallPictureInPictureBridge callPipBridge;
    private NativeChatLocationMapFactory chatLocationMapFactory;
    private String pendingInvite;
    private static final String SYSTEM_SHARE_CHANNEL = "openim_system_share";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        chatLocationMapFactory = new NativeChatLocationMapFactory(
                getLifecycle(), flutterEngine.getDartExecutor().getBinaryMessenger());
        flutterEngine.getPlatformViewsController().getRegistry().registerViewFactory(
                "openim/chat-location-map", chatLocationMapFactory);
        liveCastBridge = new LiveCastBridge(
                this, flutterEngine.getDartExecutor().getBinaryMessenger());
        callPipBridge = new CallPictureInPictureBridge(
                this, flutterEngine.getDartExecutor().getBinaryMessenger());
        pendingInvite = getIntent().getDataString();
        inviteChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "openim_friend_invites");
        inviteChannel.setMethodCallHandler((call, result) -> {
            if ("takeInvite".equals(call.method)) {
                String value = pendingInvite;
                pendingInvite = null;
                result.success(value);
            } else result.notImplemented();
        });

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

    @Override
    public void cleanUpFlutterEngine(FlutterEngine flutterEngine) {
        if (chatLocationMapFactory != null) {
            chatLocationMapFactory.dispose();
            chatLocationMapFactory = null;
        }
        if (callPipBridge != null) {
            callPipBridge.dispose();
            callPipBridge = null;
        }
        if (liveCastBridge != null) {
            liveCastBridge.dispose();
            liveCastBridge = null;
        }
        super.cleanUpFlutterEngine(flutterEngine);
    }

    @Override
    public void onUserLeaveHint() {
        if (callPipBridge != null) callPipBridge.onUserLeaveHint();
        super.onUserLeaveHint();
    }

    @Override
    public void onPictureInPictureModeChanged(boolean inPip, Configuration config) {
        super.onPictureInPictureModeChanged(inPip, config);
        if (callPipBridge != null) callPipBridge.onModeChanged(inPip);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (callPipBridge != null) callPipBridge.onResume();
    }

    @Override
    protected void onPause() {
        if (callPipBridge != null) callPipBridge.onPause();
        super.onPause();
    }

    @Override
    protected void onStop() {
        if (callPipBridge != null) callPipBridge.onStop();
        super.onStop();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        pendingInvite = intent.getDataString();
        if (inviteChannel == null || pendingInvite == null) return;
        final String value = pendingInvite;
        inviteChannel.invokeMethod("openInvite", value, new MethodChannel.Result() {
            @Override public void success(Object accepted) {
                if (Boolean.TRUE.equals(accepted) && value.equals(pendingInvite)) pendingInvite = null;
            }
            @Override public void error(String code, String message, Object details) {}
            @Override public void notImplemented() {}
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
