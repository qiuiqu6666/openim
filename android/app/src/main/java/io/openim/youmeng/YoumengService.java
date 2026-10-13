package io.openim.youmeng;

import android.app.*;
import android.content.*;
import android.os.*;
import cn.gameshield.sdk.GameShieldClient;
import io.flutter.plugin.common.MethodChannel;
import java.util.*;
import java.util.concurrent.*;

/** Owns forwarding for the application lifetime, independently of Activity recreation. */
public final class YoumengService extends Service {
    private static MethodChannel.Result pending;
    private static boolean ready;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private GameShieldClient client;

    public static synchronized void start(Context context, Map<String, Object> args, MethodChannel.Result result) {
        if (ready) { result.success(true); return; }
        if (pending != null) { result.error("BUSY", "正在启动网络保护", null); return; }
        pending = result;
        Intent intent = new Intent(context, YoumengService.class);
        intent.putExtra("cp", (String) args.get("cp"));
        intent.putExtra("token", (String) args.get("token"));
        intent.putExtra("key", (String) args.get("key"));
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent);
            else context.startService(intent);
        } catch (RuntimeException error) { complete(false); }
    }

    private static void complete(boolean success) {
        new Handler(Looper.getMainLooper()).post(() -> {
            MethodChannel.Result result;
            synchronized (YoumengService.class) { ready = success; result = pending; pending = null; }
            if (result != null) {
                if (success) result.success(true);
                else result.error("START_FAILED", "网络保护启动失败，请检查配置和转发规则", null);
            }
        });
    }

    @Override public void onCreate() {
        super.onCreate();
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
        if (intent == null) { stopSelf(); return START_NOT_STICKY; }
        final String cp = intent.getStringExtra("cp"), token = intent.getStringExtra("token"), key = intent.getStringExtra("key");
        worker.execute(() -> {
            try {
                client = new GameShieldClient(cp, token, key);
                client.start();
                if (!client.boundTcpPorts().containsAll(Arrays.asList(10008, 10002, 10001, 8815)))
                    throw new IllegalStateException("Missing service rule");
                complete(true);
            } catch (Exception error) {
                if (client != null) { try { client.stop(); } catch (Exception ignored) {} client = null; }
                stopSelf();
            }
        });
        return START_NOT_STICKY;
    }

    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        synchronized (YoumengService.class) { ready = false; }
        worker.execute(() -> {
            try { if (client != null) client.stop(); }
            finally { client = null; complete(false); }
        });
        worker.shutdown();
        super.onDestroy();
    }
}
