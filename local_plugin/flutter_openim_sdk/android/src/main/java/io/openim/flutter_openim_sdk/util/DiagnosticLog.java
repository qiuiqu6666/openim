package io.openim.flutter_openim_sdk.util;

import android.util.Log;
import java.util.regex.Pattern;
import open_im_sdk.Open_im_sdk;

/** Changes diagnostic presentation only; never changes callback data. */
public final class DiagnosticLog {
    private static final Pattern BRAND = Pattern.compile("open[-_]?im", Pattern.CASE_INSENSITIVE);
    private DiagnosticLog() {}
    public static String clean(String value) {
        return BRAND.matcher(value == null ? "" : value).replaceAll("chat");
    }
    public static void detail(String tag, String message) {
        if (Open_im_sdk.getDiagnosticLoggingSeconds() > 0) Log.i(tag, clean(message));
    }
    public static void error(String message) { Log.e("ChatSDK", clean(message)); }
}
