package chat.chat99.qr;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import androidx.exifinterface.media.ExifInterface;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileOutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Decodes with platform codecs (including supported HEIF), without resizing. */
public final class QrImageDecoderPlugin implements FlutterPlugin {
    private MethodChannel channel;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean busy = new AtomicBoolean();
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean attached;
    private File cache;
    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        attached = true;
        cache = binding.getApplicationContext().getCacheDir();
        channel = new MethodChannel(binding.getBinaryMessenger(), "99chat/qr_image_decoder");
        channel.setMethodCallHandler((call, result) -> {
            boolean text = call.method.equals("recognizeText");
            if (!text && !call.method.equals("decode")) { result.notImplemented(); return; }
            String path = call.argument("path");
            if (path == null) { result.error("invalidImage", "Invalid image", null); return; }
            if (!busy.compareAndSet(false, true)) { result.error("busy", "Busy", null); return; }
            executor.execute(() -> {
                if (text) {
                    String recognized = null;
                    try {
                        recognized = ImageTextRecognizer.recognize(binding.getApplicationContext(), path);
                    } catch (Exception | OutOfMemoryError ignored) { }
                    String reply = recognized;
                    busy.set(false);
                    main.post(() -> {
                        if (!attached) return;
                        if (reply == null) result.error("textUnavailable", "Text recognition failed", null);
                        else result.success(reply);
                    });
                    return;
                }
                Map<String, Object> value = null;
                String error = "invalidImage";
                try { value = decode(path); }
                catch (LimitException e) { error = "tooLarge"; }
                catch (OutOfMemoryError e) { error = "tooLarge"; }
                catch (Exception ignored) { }
                Map<String, Object> reply = value;
                String code = error;
                busy.set(false);
                main.post(() -> {
                    if (!attached) {
                        if (reply != null) new File((String) reply.get("path")).delete();
                        return;
                    }
                    if (reply == null) result.error(code, "Image cannot be decoded", null);
                    else result.success(reply);
                });
            });
        });
    }
    private Map<String, Object> decode(String path) throws Exception {
        File input = new File(path);
        if (input.length() > 32L * 1024 * 1024) throw new LimitException();
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(path, bounds);
        int w = bounds.outWidth, h = bounds.outHeight;
        if (w <= 0 || h <= 0) throw new Exception();
        if ((long) w * h > 16L * 1024 * 1024 || w > 32768 || h > 32768) throw new LimitException();
        Runtime runtime = Runtime.getRuntime();
        long available = runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory());
        // Reserve space for the platform's bitmap plus codec scratch buffers.
        if ((long) w * h * 8 > available) throw new LimitException();
        int orientation = new ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1);
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        Bitmap bitmap = BitmapFactory.decodeFile(path, options);
        if (bitmap == null) throw new Exception();
        File output = null;
        try {
            output = File.createTempFile("qr-local-", ".lum", cache);
            try (FileOutputStream stream = new FileOutputStream(output)) {
                int[] row = new int[w];
                byte[] gray = new byte[w];
                for (int y = 0; y < h; y++) {
                    bitmap.getPixels(row, 0, w, 0, y, w, 1);
                    for (int x = 0; x < w; x++) {
                        int p = row[x], alpha = p >>> 24;
                        int luminance = (77 * ((p >> 16) & 255) + 150 * ((p >> 8) & 255) + 29 * (p & 255)) >> 8;
                        gray[x] = (byte) ((luminance * alpha + 255 * (255 - alpha)) / 255);
                    }
                    stream.write(gray);
                }
            }
            Map<String, Object> value = new HashMap<>();
            value.put("path", output.getAbsolutePath());
            value.put("width", w); value.put("height", h);
            value.put("orientation", orientation);
            return value;
        } catch (Exception | OutOfMemoryError e) {
            if (output != null) output.delete();
            throw e;
        } finally { bitmap.recycle(); }
    }
    private static class LimitException extends Exception { }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        attached = false;
        channel.setMethodCallHandler(null);
        executor.shutdown();
    }
}
