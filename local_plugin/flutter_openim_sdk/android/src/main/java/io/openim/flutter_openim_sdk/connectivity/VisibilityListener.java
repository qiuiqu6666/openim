package io.openim.flutter_openim_sdk.connectivity;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.Log;
import io.openim.flutter_openim_sdk.FlutterOpenimSdkPlugin;
import open_im_sdk.Open_im_sdk;

/** Reports application visibility, with one native request and one latest intent. */
public class VisibilityListener implements Application.ActivityLifecycleCallbacks {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Set<Activity> started = Collections.newSetFromMap(new IdentityHashMap<>());
    private Application application;
    private Boolean reported;
    private boolean pending;
    private boolean background = true;

    public boolean isBackground() { return background; }
    public void resetReport() { reported = null; report(); }
    public void registerApplication(Application app) {
        if (application != null) return;
        application = app;
        application.registerActivityLifecycleCallbacks(this);
    }

    public void register(Activity activity) {
        if (activity == null || application != null) return;
        application = activity.getApplication();
        application.registerActivityLifecycleCallbacks(this);
    }

    public void unregisterReceiver(Activity activity) {
        if (application != null) application.unregisterActivityLifecycleCallbacks(this);
        application = null;
        started.clear();
        reported = null;
    }

    private void report() {
        if (application == null || pending || !io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().isInitialized()
                || (reported != null && reported == background)) return;
        pending = true;
        final boolean sending = background;
        Open_im_sdk.setAppBackgroundStatus(new open_im_sdk_callback.Base() {
            @Override public void onSuccess(String value) { finish(null); }
            @Override public void onError(int code, String error) { finish(code); }
            private void finish(Integer errorCode) {
                main.post(() -> {
                    pending = false;
                    if (errorCode == null) reported = sending;
                    else Log.w("VisibilityListener", "background report failed code=" + errorCode);
                    if (sending != background) report();
                });
            }
        }, String.valueOf(System.currentTimeMillis()), sending);
    }

    @Override public void onActivityStarted(@NonNull Activity activity) {
        started.add(activity);
        background = false;
        report();
    }
    @Override public void onActivityResumed(@NonNull Activity activity) {
        // Registration may happen after onStart during Flutter engine attachment.
        started.add(activity);
        background = false;
        report();
    }
    @Override public void onActivityStopped(@NonNull Activity activity) {
        started.remove(activity);
        if (started.isEmpty() && !activity.isChangingConfigurations()) {
            background = true;
            report();
        }
    }
    @Override public void onActivityPaused(@NonNull Activity activity) {}
    @Override public void onActivityCreated(@NonNull Activity activity, @Nullable Bundle state) {}
    @Override public void onActivitySaveInstanceState(@NonNull Activity activity, @NonNull Bundle state) {}
    @Override public void onActivityDestroyed(@NonNull Activity activity) { started.remove(activity); }
}
