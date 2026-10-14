package io.openim.location;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import com.amap.api.maps.model.LatLng;
import com.amap.api.services.core.LatLonPoint;
import com.amap.api.services.core.PoiItemV2;
import com.amap.api.services.core.ServiceSettings;
import com.amap.api.services.poisearch.PoiResultV2;
import com.amap.api.services.poisearch.PoiSearchV2;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import io.flutter.plugin.common.MethodChannel;

/** Owned by a consented map. Search failures never invalidate map selection. */
final class ChatLocationPlaceSearch {
    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private MethodChannel.Result pending;
    private volatile long revision;
    private volatile boolean disposed;

    ChatLocationPlaceSearch(Context context) {
        this.context = context;
    }

    void search(String text, LatLng center, MethodChannel.Result result) {
        cancel();
        if (disposed) { result.error("unavailable", "Map closed", null); return; }
        pending = result;
        final long request = revision;
        worker.execute(() -> {
            if (disposed || request != revision) return;
            try {
                ServiceSettings.updatePrivacyShow(context, true, true);
                ServiceSettings.updatePrivacyAgree(context, true);
                PoiSearchV2.Query query = new PoiSearchV2.Query(text,
                        text.isEmpty() ? "050000|060000|070000|080000|090000|100000|110000|120000|130000|140000|150000|160000|170000" : "", "");
                query.setPageSize(20);
                query.setPageNum(1);
                PoiSearchV2 search = new PoiSearchV2(context, query);
                if (center != null) search.setBound(new PoiSearchV2.SearchBound(
                        new LatLonPoint(center.latitude, center.longitude), text.isEmpty() ? 1000 : 50000));
                PoiResultV2 response = search.searchPOI();
                if (response == null) throw new IllegalStateException("Search unavailable");
                List<Map<String, Object>> rows = new ArrayList<>();
                if (response.getPois() != null) for (PoiItemV2 item : response.getPois()) {
                    LatLonPoint point = item.getLatLonPoint();
                    if (point == null || !ChatLocationCoordinates.isValid(point.getLatitude(), point.getLongitude())) continue;
                    double[] wgs = ChatLocationCoordinates.gcj02ToWgs84(point.getLatitude(), point.getLongitude());
                    Map<String, Object> row = new HashMap<>();
                    row.put("id", item.getPoiId());
                    row.put("name", item.getTitle());
                    row.put("address", item.getSnippet());
                    row.put("latitude", wgs[0]);
                    row.put("longitude", wgs[1]);
                    rows.add(row);
                }
                main.post(() -> {
                    if (disposed || request != revision || pending != result) return;
                    pending = null;
                    result.success(rows);
                });
            } catch (Exception | LinkageError error) {
                main.post(() -> {
                    if (disposed || request != revision || pending != result) return;
                    pending = null;
                    result.error("searchUnavailable", "Place search unavailable", null);
                });
            }
        });
    }

    void cancel() {
        revision++;
        if (pending != null) {
            pending.error("cancelled", "Search cancelled", null);
            pending = null;
        }
    }

    void dispose() {
        disposed = true;
        cancel();
        worker.shutdownNow();
        main.removeCallbacksAndMessages(null);
    }
}
