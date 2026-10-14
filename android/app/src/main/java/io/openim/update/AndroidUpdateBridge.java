package io.openim.update;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** DownloadManager owns background transfers; this bridge only polls while
 * Flutter is active. APK verification/copying never runs on the UI thread. */
public final class AndroidUpdateBridge {
    private final Activity activity;
    private final DownloadManager downloads;
    private final SharedPreferences prefs;
    private final MethodChannel channel;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private boolean disposed;

    public AndroidUpdateBridge(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        downloads = (DownloadManager) activity.getSystemService(Context.DOWNLOAD_SERVICE);
        prefs = activity.getSharedPreferences("android_update", Context.MODE_PRIVATE);
        channel = new MethodChannel(messenger, "openim/android_update");
        channel.setMethodCallHandler((call, result) -> {
            if ("canInstall".equals(call.method)) {
                result.success(Build.VERSION.SDK_INT < 26 || activity.getPackageManager().canRequestPackageInstalls());
                return;
            }
            if ("permission".equals(call.method)) {
                try {
                    if (Build.VERSION.SDK_INT >= 26) activity.startActivity(new Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.getPackageName())));
                    result.success(null);
                } catch (Exception error) { result.error("permission", error.getMessage(), null); }
                return;
            }
            worker.execute(() -> {
                try {
                    Object value = null;
                    Map<String, Object> args = call.arguments();
                    switch (call.method) {
                        case "enqueue": enqueue(args); break;
                        case "status": value = status(); break;
                        case "clear": clear(); break;
                        case "verify": prepare(args); break;
                        case "install":
                            requireKey(args);
                            UpdatePackageVerifier.verify(activity, readyFile(), args);
                            activity.runOnUiThread(() -> {
                                if (disposed) { result.error("closed", "Activity closed", null); return; }
                                try {
                                    Uri uri = FileProvider.getUriForFile(activity,
                                            activity.getPackageName() + ".fileProvider", readyFile());
                                    Intent intent = new Intent(Intent.ACTION_VIEW)
                                            .setDataAndType(uri, "application/vnd.android.package-archive")
                                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                    activity.startActivity(intent);
                                    result.success(null);
                                } catch (Exception error) { result.error("install", error.getMessage(), null); }
                            });
                            return;
                        default:
                            activity.runOnUiThread(result::notImplemented); return;
                    }
                    final Object response = value;
                    activity.runOnUiThread(() -> result.success(response));
                } catch (Exception error) {
                    activity.runOnUiThread(() -> result.error("update", error.getMessage(), null));
                }
            });
        });
    }

    private File downloadFile() {
        File dir = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        if (dir == null) throw new IllegalStateException("Download storage unavailable");
        return new File(dir, "pending-update.apk");
    }
    private File readyFile() { return new File(activity.getFilesDir(), "updates/ready.apk"); }
    private void requireKey(Map<String, Object> args) {
        if (!prefs.getString("key", "").equals(args.get("key")))
            throw new IllegalStateException("Release changed");
    }
    private void enqueue(Map<String, Object> args) throws Exception {
        Uri uri = Uri.parse((String) args.get("url"));
        if (!"https".equals(uri.getScheme()) || uri.getHost() == null
                || !String.valueOf(args.get("sha256")).matches("[a-f0-9]{64}")
                || UpdatePackageVerifier.number(args, "size") <= 0)
            throw new IllegalArgumentException("Invalid release metadata");
        if (prefs.getString("key", "").equals(args.get("key"))) {
            String state = (String) status().get("state");
            if (!"missing".equals(state) && !"failed".equals(state)) return;
        }
        clear();
        File file = downloadFile();
        if (!file.getParentFile().isDirectory() && !file.getParentFile().mkdirs())
            throw new IllegalStateException("Cannot create download directory");
        if (file.getParentFile().getUsableSpace() < UpdatePackageVerifier.number(args, "size") * 2L)
            throw new IllegalStateException("Insufficient storage");
        DownloadManager.Request request = new DownloadManager.Request(uri)
                .setTitle("99Chat 更新")
                .setDescription("正在后台准备安装包")
                .setMimeType("application/vnd.android.package-archive")
                .setDestinationUri(Uri.fromFile(file))
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(false);
        long id = downloads.enqueue(request);
        if (!prefs.edit().putLong("id", id).putString("key", (String) args.get("key")).commit()) {
            downloads.remove(id);
            throw new IllegalStateException("Cannot persist download task");
        }
    }
    private Map<String, Object> status() {
        Map<String, Object> out = new HashMap<>();
        out.put("state", "missing");
        long id = prefs.getLong("id", -1);
        if (id == -1) return out;
        try (Cursor cursor = downloads.query(new DownloadManager.Query().setFilterById(id))) {
            if (cursor == null || !cursor.moveToFirst()) return out;
            int state = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
            out.put("state", state == DownloadManager.STATUS_SUCCESSFUL ? "complete" :
                    state == DownloadManager.STATUS_FAILED ? "failed" : "downloading");
            out.put("bytes", cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)));
            out.put("total", cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)));
        }
        return out;
    }
    private void prepare(Map<String, Object> args) throws Exception {
        requireKey(args);
        if (!"complete".equals(status().get("state"))) throw new IllegalStateException("Download incomplete");
        File ready = readyFile();
        if (!ready.getParentFile().isDirectory() && !ready.getParentFile().mkdirs())
            throw new IllegalStateException("Cannot prepare APK");
        // Copy from external app storage into private storage before verifying.
        // The installer receives only the verified private copy.
        try (FileInputStream input = new FileInputStream(downloadFile());
             FileOutputStream output = new FileOutputStream(ready)) {
            byte[] buffer = new byte[128 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            output.getFD().sync();
        }
        try { UpdatePackageVerifier.verify(activity, ready, args); }
        catch (Exception error) { ready.delete(); throw error; }
    }
    private void clear() {
        long id = prefs.getLong("id", -1);
        if (id != -1) downloads.remove(id);
        downloadFile().delete();
        readyFile().delete();
        prefs.edit().clear().commit();
    }
    public void dispose() {
        disposed = true;
        channel.setMethodCallHandler(null);
        worker.shutdown();
    }
}
