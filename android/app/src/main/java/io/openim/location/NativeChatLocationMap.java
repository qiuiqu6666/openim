package io.openim.location;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;

import com.amap.api.maps.AMap;
import com.amap.api.maps.AMapOptions;
import com.amap.api.maps.CameraUpdateFactory;
import com.amap.api.maps.CoordinateConverter;
import com.amap.api.maps.MapView;
import com.amap.api.maps.MapsInitializer;
import com.amap.api.maps.model.AMapGestureListener;
import com.amap.api.maps.model.BitmapDescriptorFactory;
import com.amap.api.maps.model.CameraPosition;
import com.amap.api.maps.model.LatLng;
import com.amap.api.maps.model.Marker;
import com.amap.api.maps.model.MarkerOptions;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;

/** AMap display and gestures only. Location permission remains owned by Dart. */
public final class NativeChatLocationMap implements PlatformView, DefaultLifecycleObserver {
    private final Context context;
    private final FrameLayout container;
    private final MethodChannel channel;
    private final Lifecycle lifecycle;
    private final Consumer<NativeChatLocationMap> onDisposed;
    private final Handler main = new Handler(Looper.getMainLooper());
    private MapView mapView;
    private AMap map;
    private Marker marker;
    private volatile boolean disposed;
    private volatile boolean active = true;
    private volatile boolean hostResumed;
    private volatile long generation;
    private boolean resumed;
    private boolean ready;
    private boolean pointerDown;
    private boolean userPanning;
    private LatLng panStart;
    private LatLng pendingWgsPoint;
    private float pendingZoom = 16f;
    private String error;

    NativeChatLocationMap(Context context, Lifecycle lifecycle, BinaryMessenger messenger,
                          int viewId, Map<?, ?> params,
                          Consumer<NativeChatLocationMap> onDisposed) {
        this.context = context;
        this.lifecycle = lifecycle;
        this.onDisposed = onDisposed;
        container = new FrameLayout(context);
        channel = new MethodChannel(messenger, "openim/chat-location-map/" + viewId);
        channel.setMethodCallHandler(this::handle);
        hostResumed = lifecycle.getCurrentState().isAtLeast(Lifecycle.State.RESUMED);
        if (params == null || !Boolean.TRUE.equals(params.get("privacyAgreed"))) {
            error = "consentRequired";
        } else if (!hasApiKey()) {
            error = "keyMissing";
        } else {
            initialize(params);
        }
        lifecycle.addObserver(this);
        syncLifecycle();
        if (error != null) emit("onError", code(error));
    }

    private boolean hasApiKey() {
        try {
            ApplicationInfo info = context.getPackageManager().getApplicationInfo(
                    context.getPackageName(), PackageManager.GET_META_DATA);
            String key = info.metaData == null ? null : info.metaData.getString("com.amap.api.v2.apikey");
            return key != null && !key.trim().isEmpty();
        } catch (Exception ignored) {
            return false;
        }
    }

    private void initialize(Map<?, ?> params) {
        try {
            // These must precede construction or invocation of any other SDK API.
            MapsInitializer.updatePrivacyShow(context, true, true);
            MapsInitializer.updatePrivacyAgree(context, true);
            MapsInitializer.setProtocol(MapsInitializer.HTTPS);
            AMapOptions options = new AMapOptions()
                    .mapType(Boolean.TRUE.equals(params.get("dark")) ? AMap.MAP_TYPE_NIGHT : AMap.MAP_TYPE_NORMAL)
                    .scaleControlsEnabled(true).zoomControlsEnabled(false)
                    .compassEnabled(false).tiltGesturesEnabled(false).rotateGesturesEnabled(false);
            LatLng initial = readWgs84(params);
            LatLng initialNative = initial == null ? null : toNative(initial);
            if (initialNative != null) options.camera(CameraPosition.fromLatLngZoom(initialNative, 16f));
            mapView = new MapView(context, options);
            mapView.onCreate(new Bundle());
            map = mapView.getMap();
            if (map == null) throw new IllegalStateException("Map unavailable");
            map.setMyLocationEnabled(false);
            map.getUiSettings().setMyLocationButtonEnabled(false);
            map.setOnMapClickListener(point -> dispatch(() -> select(point)));
            map.setOnMapLoadedListener(() -> main.post(() -> {
                // A covered view may finish loading; remember readiness for its return.
                if (disposed || map == null || error != null) return;
                ready = true;
                if (active && hostResumed) emit("onReady", null);
            }));
            map.setAMapGestureListener(new AMapGestureListener() {
                @Override public void onDown(float x, float y) {
                    dispatch(() -> {
                        pointerDown = true;
                        userPanning = false;
                        panStart = map.getCameraPosition().target;
                    });
                }
                @Override public void onScroll(float x, float y) {
                    dispatch(() -> { if (pointerDown) userPanning = true; });
                }
                @Override public void onUp(float x, float y) {
                    dispatch(() -> pointerDown = false);
                }
                @Override public void onMapStable() { dispatch(() -> finishPan(map.getCameraPosition().target)); }
                @Override public void onDoubleTap(float x, float y) {}
                @Override public void onSingleTap(float x, float y) {}
                @Override public void onFling(float x, float y) {}
                @Override public void onLongPress(float x, float y) {}
            });
            map.setOnCameraChangeListener(new AMap.OnCameraChangeListener() {
                @Override public void onCameraChange(CameraPosition position) {}
                @Override public void onCameraChangeFinish(CameraPosition position) {
                    dispatch(() -> finishPan(position.target));
                }
            });
            if (initialNative != null) updateMarker(initialNative);
            container.addView(mapView, new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        } catch (Exception | LinkageError ignored) {
            fail();
        }
    }

    private void handle(MethodCall call, MethodChannel.Result result) {
        if ("status".equals(call.method)) {
            Map<String, Object> status = new HashMap<>();
            status.put("error", disposed ? "unavailable" : error);
            result.success(status);
            return;
        }
        if ("dispose".equals(call.method)) {
            dispose();
            result.success(null);
            return;
        }
        if (disposed) { result.success(null); return; }
        Map<?, ?> args = call.arguments instanceof Map ? (Map<?, ?>) call.arguments : null;
        try {
            switch (call.method) {
                case "move":
                    if (map != null && error == null && args != null) {
                        LatLng coordinate = readWgs84(args);
                        if (coordinate != null) {
                            Number zoom = args.get("zoom") instanceof Number ? (Number) args.get("zoom") : null;
                            pendingZoom = zoom == null || Double.isNaN(zoom.doubleValue())
                                    || Double.isInfinite(zoom.doubleValue())
                                    ? 16f : Math.max(3f, Math.min(20f, zoom.floatValue()));
                            pendingWgsPoint = coordinate;
                            applyPendingMove();
                        }
                    }
                    result.success(null);
                    break;
                case "style":
                    if (map != null && args != null) map.setMapType(Boolean.TRUE.equals(args.get("dark"))
                            ? AMap.MAP_TYPE_NIGHT : AMap.MAP_TYPE_NORMAL);
                    result.success(null);
                    break;
                case "setActive":
                    boolean next = args != null && Boolean.TRUE.equals(args.get("active"));
                    if (active != next) {
                        active = next;
                        generation++;
                        clearGesture();
                        syncLifecycle();
                        if (active && hostResumed) {
                            if (error != null) emit("onError", code(error));
                            else if (ready) emit("onReady", null);
                        }
                    }
                    result.success(null);
                    break;
                default: result.notImplemented();
            }
        } catch (Exception | LinkageError ignored) {
            fail();
            result.success(null);
        }
    }

    private LatLng toNative(LatLng wgs84) {
        if (!usesGcj02(wgs84)) return wgs84;
        LatLng converted = new CoordinateConverter(context).from(CoordinateConverter.CoordType.GPS)
                .coord(wgs84).convert();
        if (converted == null || !ChatLocationCoordinates.isValid(converted.latitude, converted.longitude)) {
            throw new IllegalStateException("Coordinate unavailable");
        }
        // convert() catches native failures and can return the original WGS84 point.
        if (Math.abs(converted.latitude - wgs84.latitude) <= 1e-10
                && Math.abs(converted.longitude - wgs84.longitude) <= 1e-10) {
            throw new IllegalStateException("Coordinate unavailable");
        }
        return converted;
    }

    private void applyPendingMove() {
        if (!usable() || pendingWgsPoint == null) return;
        LatLng point = pendingWgsPoint;
        float zoom = pendingZoom;
        pendingWgsPoint = null;
        clearGesture();
        generation++;
        LatLng nativePoint = toNative(point);
        map.stopAnimation();
        updateMarker(nativePoint);
        map.moveCamera(CameraUpdateFactory.newLatLngZoom(nativePoint, zoom));
    }

    private static LatLng readWgs84(Map<?, ?> values) {
        Object latitude = values.get("latitude");
        Object longitude = values.get("longitude");
        if (!(latitude instanceof Number) || !(longitude instanceof Number)) return null;
        double lat = ((Number) latitude).doubleValue();
        double lng = ((Number) longitude).doubleValue();
        return ChatLocationCoordinates.isValid(lat, lng) ? new LatLng(lat, lng) : null;
    }

    private static boolean usesGcj02(LatLng point) {
        return ChatLocationCoordinates.insideChina(point.latitude, point.longitude)
                && CoordinateConverter.isAMapDataAvailable(point.latitude, point.longitude);
    }

    private void finishPan(LatLng point) {
        if (!userPanning || pointerDown || panStart == null || point == null) return;
        LatLng current = map.getCameraPosition().target;
        if (current == null || Math.abs(point.latitude - current.latitude) > 1e-7
                || Math.abs(point.longitude - current.longitude) > 1e-7) return;
        boolean changed = Math.abs(point.latitude - panStart.latitude) > 1e-7
                || Math.abs(point.longitude - panStart.longitude) > 1e-7;
        clearGesture();
        if (changed) select(point);
    }

    private void select(LatLng nativePoint) {
        if (!usable() || nativePoint == null
                || !ChatLocationCoordinates.isValid(nativePoint.latitude, nativePoint.longitude)) return;
        clearGesture();
        updateMarker(nativePoint);
        double[] wgs84 = usesGcj02(nativePoint)
                ? ChatLocationCoordinates.gcj02ToWgs84(nativePoint.latitude, nativePoint.longitude)
                : new double[]{nativePoint.latitude, nativePoint.longitude};
        Map<String, Object> coordinate = new HashMap<>();
        coordinate.put("latitude", wgs84[0]);
        coordinate.put("longitude", wgs84[1]);
        emit("onSelected", coordinate);
    }

    private void updateMarker(LatLng point) {
        if (marker == null) {
            marker = map.addMarker(new MarkerOptions().position(point).anchor(0.5f, 1f)
                    .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE)));
        } else marker.setPosition(point);
    }

    private boolean usable() { return !disposed && active && hostResumed && error == null && map != null; }

    private void clearGesture() { pointerDown = false; userPanning = false; panStart = null; }

    private void dispatch(Runnable action) {
        final long revision = generation;
        main.post(() -> {
            if (revision != generation || !usable()) return;
            try { action.run(); } catch (Exception | LinkageError ignored) { fail(); }
        });
    }

    private void emit(String method, Object arguments) {
        final long revision = generation;
        main.post(() -> {
            if (!disposed && active && hostResumed && revision == generation) {
                channel.invokeMethod(method, arguments);
            }
        });
    }

    private static Map<String, Object> code(String error) {
        Map<String, Object> result = new HashMap<>();
        result.put("code", error);
        return result;
    }

    private void fail() {
        error = "unavailable";
        generation++;
        clearGesture();
        destroyMap();
        emit("onError", code(error));
    }

    private void syncLifecycle() {
        if (mapView == null || disposed) return;
        boolean shouldResume = active && hostResumed && error == null;
        if (resumed == shouldResume) return;
        try {
            if (shouldResume) mapView.onResume();
            else mapView.onPause();
            resumed = shouldResume;
            if (shouldResume) applyPendingMove();
        } catch (Exception | LinkageError ignored) { fail(); }
    }

    @Override public void onResume(@NonNull LifecycleOwner owner) {
        hostResumed = true;
        syncLifecycle();
        if (active && !disposed) {
            if (error != null) emit("onError", code(error));
            else if (ready) emit("onReady", null);
        }
    }

    @Override public void onPause(@NonNull LifecycleOwner owner) {
        hostResumed = false;
        generation++;
        clearGesture();
        syncLifecycle();
    }

    @Override public void onDestroy(@NonNull LifecycleOwner owner) { dispose(); }

    @Override public View getView() { return container; }

    @Override public void dispose() {
        if (disposed) return;
        disposed = true;
        generation++;
        pendingWgsPoint = null;
        clearGesture();
        main.removeCallbacksAndMessages(null);
        channel.setMethodCallHandler(null);
        lifecycle.removeObserver(this);
        destroyMap();
        onDisposed.accept(this);
    }

    private void destroyMap() {
        if (map != null) {
            try {
                map.setOnMapClickListener(null);
                map.setOnMapLoadedListener(null);
                map.setOnCameraChangeListener(null);
                map.setAMapGestureListener(null);
                if (marker != null) marker.remove();
            } catch (Exception | LinkageError ignored) {}
        }
        marker = null;
        map = null;
        if (mapView != null) {
            if (resumed) {
                try { mapView.onPause(); } catch (Exception | LinkageError ignored) {}
            }
            try { mapView.onDestroy(); } catch (Exception | LinkageError ignored) {}
            container.removeView(mapView);
            mapView = null;
        }
        resumed = false;
    }
}
