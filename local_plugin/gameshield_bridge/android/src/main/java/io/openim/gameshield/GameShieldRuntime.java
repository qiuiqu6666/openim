package io.openim.gameshield;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

final class GameShieldRuntime {
    static final GameShieldRuntime INSTANCE = new GameShieldRuntime();
    private GameShieldRuntime() {}
    private final ExecutorService worker = new java.util.concurrent.ThreadPoolExecutor(1, 1, 0L,
            java.util.concurrent.TimeUnit.MILLISECONDS, new java.util.concurrent.ArrayBlockingQueue<>(32));
    private final java.util.concurrent.atomic.AtomicBoolean networkQueued = new java.util.concurrent.atomic.AtomicBoolean();
    private final java.util.concurrent.atomic.AtomicBoolean foregroundPending = new java.util.concurrent.atomic.AtomicBoolean();
    private final Handler main = new Handler(Looper.getMainLooper());
    private Context context;
    private GameShieldAndroidClient client;
    private boolean monitoring;
    private ConnectivityManager connectivity;
    private Application application;
    private final ConnectivityManager.NetworkCallback network = new ConnectivityManager.NetworkCallback() {
        private Network current;
        private boolean validated;
        @Override public void onAvailable(Network value) {
            current = value; validated = false; notifyClient(false);
        }
        @Override public void onLost(Network value) {
            if (value.equals(current)) { current = null; validated = false; notifyClient(false); }
        }
        @Override public void onCapabilitiesChanged(Network value, NetworkCapabilities caps) {
            if (!value.equals(current)) return;
            boolean next = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
            if (next && !validated) notifyClient(false);
            validated = next;
        }
    };
    private final Application.ActivityLifecycleCallbacks lifecycle = new Application.ActivityLifecycleCallbacks() {
        @Override public void onActivityResumed(Activity value) { notifyClient(true); }
        @Override public void onActivityCreated(Activity value, Bundle state) {}
        @Override public void onActivityStarted(Activity value) {}
        @Override public void onActivityPaused(Activity value) {}
        @Override public void onActivityStopped(Activity value) {}
        @Override public void onActivitySaveInstanceState(Activity value, Bundle state) {}
        @Override public void onActivityDestroyed(Activity value) {}
    };
    synchronized void attach(Context app) {
        if (context != null) return;
        context = app.getApplicationContext();
        connectivity = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        application = (Application) context;
    }
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (!"start".equals(call.method) && !"status".equals(call.method) && !"stop".equals(call.method)) {
            result.notImplemented(); return;
        }
        final String token = "start".equals(call.method) ? call.argument("licenseToken") : null;
        if ("start".equals(call.method) && (token == null || !token.startsWith("GS2."))) {
            result.error("TOKEN_INVALID", "GameShield credentials are not configured.", null); return;
        }
        try { worker.execute(() -> {
            try {
                if ("stop".equals(call.method)) {
                    stop(); reply(result, null); return;
                }
                if ("start".equals(call.method) && client == null) {
                    if (!GameShieldAndroidClient.available()) {
                        main.post(() -> { result.error("SDK_UNAVAILABLE",
                                "A compatible GameShield SDK has not been installed.", null); });
                        return;
                    }
                    client = new GameShieldAndroidClient(context, token);
                    client.start();
                    monitor();
                }
                if (client == null) {
                    main.post(() -> { result.error("SDK_NOT_STARTED", "GameShield is not running.", null); });
                    return;
                }
                reply(result, client.snapshot());
            } catch (Throwable error) {
                if ("start".equals(call.method)) { try { stop(); } catch (Exception ignored) {} }
                // Native exception messages may contain credentials. Do not log or forward them.
                main.post(() -> { result.error("NATIVE_FAILED", "GameShield operation failed.", null); });
            }
        }); } catch (RejectedExecutionException error) { result.error("NATIVE_BUSY", "GameShield queue is busy.", null); }
    }
    private void reply(MethodChannel.Result result, Object value) {
        main.post(() -> { result.success(value); });
    }
    private void notifyClient(boolean foreground) {
        if (foreground) foregroundPending.set(true);
        if (!networkQueued.compareAndSet(false, true)) return;
        try {
            worker.execute(() -> {
                networkQueued.set(false);
                if (client == null) return;
                try {
                    if (foregroundPending.getAndSet(false)) client.foreground();
                    client.networkChanged();
                } catch (Exception ignored) {}
            });
        } catch (RejectedExecutionException ignored) { networkQueued.set(false); }
    }
    private void monitor() {
        if (monitoring) return;
        connectivity.registerDefaultNetworkCallback(network);
        monitoring = true;
        application.registerActivityLifecycleCallbacks(lifecycle);
    }
    private void stop() throws Exception {
        if (monitoring) {
            monitoring = false;
            application.unregisterActivityLifecycleCallbacks(lifecycle);
            try { connectivity.unregisterNetworkCallback(network); } catch (RuntimeException ignored) {}
        }
        GameShieldAndroidClient previous = client;
        client = null;
        if (previous != null) previous.stop();
    }
}
