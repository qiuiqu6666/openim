package io.openim.youmeng;

import android.app.*;
import android.content.*;
import android.os.*;
import cn.gameshield.sdk.GameShieldClient;
import io.flutter.plugin.common.MethodChannel;
import java.util.*;
import java.util.concurrent.*;

/** Main-thread callbacks are generation-owned; cleanup never queues behind start. */
public final class YoumengService extends Service {
    private static MethodChannel.Result pending;
    private static boolean ready;
    private static int generation;
    private static YoumengService activeService;
    private static final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private volatile GameShieldClient client;
    private volatile boolean destroyed;
    private int attempt;

    public static synchronized void start(Context context, Map<String, Object> args, MethodChannel.Result result) {
        if (ready) { result.success(true); return; }
        if (pending != null) { result.error("BUSY", "正在启动网络保护", null); return; }
        pending = result;
        final int current = ++generation;
        Intent intent = new Intent(context, YoumengService.class);
        intent.putExtra("generation", current);
        intent.putExtra("cp", (String) args.get("cp"));
        intent.putExtra("token", (String) args.get("token"));
        intent.putExtra("key", (String) args.get("key"));
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent);
            else context.startService(intent);
            main.postDelayed(() -> {
                synchronized (YoumengService.class) {
                    if (generation != current || pending == null) return;
                    cancel(context);
                }
            }, 18000);
        } catch (RuntimeException error) { complete(current, false); }
    }

    public static synchronized void cancel(Context context) {
        if (pending == null) return; // Keep an initialized standby available.
        MethodChannel.Result callback = pending;
        pending = null; ready = false; ++generation;
        // Never stop a not-yet-created foreground service: Android would kill
        // the process before it has a chance to call startForeground().
        if (activeService != null) activeService.cancelWork();
        callback.error("CANCELLED", "网络保护准备已取消", null);
    }

    private static void complete(int owner, boolean success) {
        main.post(() -> {
            MethodChannel.Result callback;
            synchronized (YoumengService.class) {
                if (owner != generation) return;
                ready = success; callback = pending; pending = null;
            }
            if (callback != null) {
                if (success) callback.success(true);
                else callback.error("START_FAILED", "网络保护启动失败", null);
            }
        });
    }

    @Override public void onCreate() {
        super.onCreate();
        promote();
        synchronized (YoumengService.class) { activeService = this; }
    }

    private void promote() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            new NotificationChannel("youmeng_shield", "网络保护", NotificationManager.IMPORTANCE_LOW));
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, "youmeng_shield") : new Notification.Builder(this);
        startForeground(7401, builder.setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("网络保护运行中").setContentText("为聊天连接提供转发服务")
            .setOngoing(true).build());
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        promote(); // Each startForegroundService request must be acknowledged.
        if (intent == null) { stopSelf(); return START_NOT_STICKY; }
        final int owner = intent.getIntExtra("generation", -1);
        synchronized (YoumengService.class) {
            if (owner != generation) { stopSelf(startId); return START_NOT_STICKY; }
        }
        attempt = owner;
        final String cp = intent.getStringExtra("cp"), token = intent.getStringExtra("token"), key = intent.getStringExtra("key");
        worker.execute(() -> {
            GameShieldClient candidate = null;
            try {
                synchronized (YoumengService.class) {
                    if (owner != generation || destroyed) return;
                    candidate = new GameShieldClient(cp, token, key);
                    client = candidate;
                }
                candidate.start();
                synchronized (YoumengService.class) {
                    if (owner != generation || destroyed) throw new IllegalStateException("Cancelled");
                }
                if (!candidate.boundTcpPorts().containsAll(Arrays.asList(10008, 10002, 10001, 8815)))
                    throw new IllegalStateException("Missing service rule");
                complete(owner, true);
            } catch (Exception error) {
                if (candidate != null) candidate.stop();
                complete(owner, false);
                stopSelf(startId);
            }
        });
        return START_NOT_STICKY;
    }

    @Override public IBinder onBind(Intent intent) { return null; }
    private void cancelWork() {
        final GameShieldClient old = client;
        if (old != null) new Thread(old::stop, "shield-cancel").start();
    }
    @Override public void onDestroy() {
        destroyed = true;
        synchronized (YoumengService.class) {
            if (activeService == this) activeService = null;
        }
        final GameShieldClient old = client; client = null;
        // Http reads may be blocked; interrupt/close outside their executor.
        if (old != null) new Thread(old::stop, "shield-cleanup").start();
        worker.shutdownNow();
        complete(attempt, false);
        super.onDestroy();
    }
}
