package io.openim.location;

import android.content.Context;
import android.location.Address;
import android.location.Geocoder;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.Locale;
import java.util.HashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** System geocoder accepts WGS84; no GPS permission or map engine is required. */
public final class ChatLocationAddressBridge {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final MethodChannel channel;
    private boolean disposed;
    public ChatLocationAddressBridge(Context context, BinaryMessenger messenger) {
        Context app = context.getApplicationContext();
        channel = new MethodChannel(messenger, "openim/location-address");
        channel.setMethodCallHandler((call, rawResult) -> {
            AtomicBoolean completed = new AtomicBoolean();
            MethodChannel.Result result = new MethodChannel.Result() {
                @Override public void success(Object value) { if (!disposed && completed.compareAndSet(false, true)) rawResult.success(value); }
                @Override public void error(String code, String message, Object details) { if (!disposed && completed.compareAndSet(false, true)) rawResult.error(code, message, details); }
                @Override public void notImplemented() { if (!disposed && completed.compareAndSet(false, true)) rawResult.notImplemented(); }
            };
            if (!"reverse".equals(call.method)) { result.notImplemented(); return; }
            Number lat = call.argument("latitude"), lon = call.argument("longitude");
            if (lat == null || lon == null || !ChatLocationCoordinates.isValid(lat.doubleValue(), lon.doubleValue())) {
                result.error("invalid", "Invalid coordinate", null); return;
            }
            if (!Geocoder.isPresent()) { result.error("unavailable", "Address service unavailable", null); return; }
            main.postDelayed(() -> result.error("timeout", "Address lookup timed out", null), 14000);
            String language = call.argument("locale");
            Geocoder geocoder = new Geocoder(app, language == null ? Locale.getDefault() : Locale.forLanguageTag(language.replace('_', '-')));
            if (Build.VERSION.SDK_INT >= 33) {
                try {
                    geocoder.getFromLocation(lat.doubleValue(), lon.doubleValue(), 1, new Geocoder.GeocodeListener() {
                        @Override public void onGeocode(List<Address> rows) { finish(result, rows); }
                        @Override public void onError(String message) { finish(result, null); }
                    });
                } catch (Exception e) { finish(result, null); }
            } else {
                worker.execute(() -> {
                    try { finish(result, geocoder.getFromLocation(lat.doubleValue(), lon.doubleValue(), 1)); }
                    catch (Exception e) { finish(result, null); }
                });
            }
        });
    }
    private void finish(MethodChannel.Result result, List<Address> rows) {
        main.post(() -> {
            if (disposed) return;
            if (rows == null || rows.isEmpty()) { result.error("unavailable", "Address not found", null); return; }
            Address address = rows.get(0);
            String line = address.getMaxAddressLineIndex() >= 0 ? address.getAddressLine(0) : null;
            if (line == null || line.trim().isEmpty()) { result.error("unavailable", "Address not found", null); return; }
            HashMap<String, Object> value = new HashMap<>();
            value.put("name", address.getFeatureName() == null ? "" : address.getFeatureName());
            value.put("address", line);
            result.success(value);
        });
    }
    public void dispose() { disposed = true; channel.setMethodCallHandler(null); worker.shutdownNow(); }
}
