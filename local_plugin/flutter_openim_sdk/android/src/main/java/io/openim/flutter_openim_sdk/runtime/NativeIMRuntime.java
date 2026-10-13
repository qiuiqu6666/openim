package io.openim.flutter_openim_sdk.runtime;

import android.app.Application;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import java.util.Map;
import java.util.HashMap;
import java.util.concurrent.CopyOnWriteArraySet;
import org.json.JSONObject;
import io.openim.flutter_openim_sdk.connectivity.ConnectivityListener;
import io.openim.flutter_openim_sdk.connectivity.VisibilityListener;
import io.openim.flutter_openim_sdk.listener.OnAdvancedMsgListener;
import io.openim.flutter_openim_sdk.listener.OnConnListener;
import open_im_sdk.Open_im_sdk;
import open_im_sdk_callback.Base;

/** Process-owned SDK. Engine/service attachment never owns or destroys Core. */
public final class NativeIMRuntime {
    public interface EventSink { void onEvent(String method, Map<String, Object> event); }
    private static final class Holder { private static final NativeIMRuntime INSTANCE = new NativeIMRuntime(); }
    public static NativeIMRuntime get() { return Holder.INSTANCE; }
    private final CoreLifecycle core;
    private final java.util.function.Consumer<Runnable> post;
    private final java.util.function.Consumer<String> diagnostic;
    private final CopyOnWriteArraySet<EventSink> nativeSinks = new CopyOnWriteArraySet<>();
    private final CopyOnWriteArraySet<EventSink> flutterSinks = new CopyOnWriteArraySet<>();
    private OnAdvancedMsgListener messages = new OnAdvancedMsgListener("", 0L);
    private String messageListenerID = "";
    private ConnectivityListener network;
    private VisibilityListener visibility;
    private volatile boolean initialized;
    private boolean sessionOperation;
    private volatile long sessionGeneration;
    private String configuration;
    private volatile String account = "";
    private String token = ""; // memory only, never emitted or persisted by this runtime
    private Map<String, Object> connectionSnapshot;
    private Map<String, Object> syncSnapshot;

    private NativeIMRuntime() {
        this(new GoCoreLifecycle(), new Handler(Looper.getMainLooper())::post,
                message -> Log.i("NativeIMRuntime", message));
    }
    NativeIMRuntime(CoreLifecycle core, java.util.function.Consumer<Runnable> post,
                    java.util.function.Consumer<String> diagnostic) {
        this.core = core; this.post = post; this.diagnostic = diagnostic;
    }
    public synchronized void attachApplication(Context context) {
        if (network != null) return;
        Context app = context.getApplicationContext();
        network = new ConnectivityListener(app);
        visibility = new VisibilityListener();
        visibility.registerApplication((Application) app);
        network.register();
    }
    public boolean isInitialized() { return initialized; }
    public String accountID() { return account; }
    public long sessionGeneration() { return sessionGeneration; }
    public boolean isForeground() { return visibility != null && !visibility.isBackground(); }
    public void addNativeSink(EventSink sink) { nativeSinks.add(sink); }
    public void attachFlutter(EventSink sink) {
        flutterSinks.add(sink);
        diagnostic.accept("Flutter attached; sinks=" + flutterSinks.size() + "; initialized=" + initialized);
    }
    public void detachFlutter(EventSink sink) {
        flutterSinks.remove(sink);
        diagnostic.accept("Flutter detached; sinks=" + flutterSinks.size() + "; initialized=" + initialized);
        if (flutterSinks.isEmpty()) emitLocal("onFlutterDetached");
    }
    public boolean hasFlutter() { return !flutterSinks.isEmpty(); }

    public synchronized boolean initialize(String operationID, String config) {
        if (sessionOperation) throw new IllegalStateException("SDK session transition in progress");
        if (initialized) {
            if (!RuntimeConfiguration.matches(configuration, config))
                throw new IllegalStateException("Explicit SDK shutdown required before changing configuration");
            replayConnection();
            return true;
        }
        initialized = core.initSDK(new OnConnListener(), operationID, config);
        if (initialized) {
            configuration = config;
            core.setAdvancedMsgListener(messages);
            diagnostic.accept("Core initialized once; version=" + core.getSdkVersion());
        }
        return initialized;
    }
    public synchronized void shutdown(String operationID) {
        if (sessionOperation) throw new IllegalStateException("SDK session transition in progress");
        clearSession();
        if (initialized) core.unInitSDK(operationID);
        initialized = false;
        configuration = null;
        connectionSnapshot = null;
        syncSnapshot = null;
        if (visibility != null) visibility.resetReport();
    }
    public synchronized void login(Base callback, String operationID, String userID, String loginToken) {
        if (!initialized) { callback.onError(-1, "SDK is not initialized"); return; }
        if (sessionOperation) { callback.onError(-1, "SDK session transition in progress"); return; }
        if (!account.isEmpty()) {
            if (account.equals(userID) && token.equals(loginToken) && core.getLoginStatus(operationID) == 3) {
                callback.onSuccess(""); replayConnection(); replaySync(); return;
            }
            callback.onError(-1, "Explicit logout required before changing account or credentials"); return;
        }
        if (core.getLoginStatus(operationID) == 3) { callback.onError(-1, "SDK still logged in; logout required"); return; }
        sessionOperation = true;
        sessionGeneration++;
        messages = new OnAdvancedMsgListener(messageListenerID, sessionGeneration);
        core.setAdvancedMsgListener(messages);
        account = userID;
        token = loginToken;
        core.login(new Base() {
            @Override public void onError(int code, String error) {
                synchronized (NativeIMRuntime.this) { sessionOperation = false; clearSession(); }
                callback.onError(code, error);
            }
            @Override public void onSuccess(String value) {
                synchronized (NativeIMRuntime.this) { sessionOperation = false; }
                post.accept(() -> { if (visibility != null) visibility.resetReport(); emitLocal("onSessionReady"); });
                callback.onSuccess(value);
            }
        }, operationID, userID, loginToken);
    }
    public synchronized void logout(Base callback, String operationID) {
        if (!initialized) { callback.onError(-1, "SDK is not initialized"); return; }
        if (sessionOperation) { callback.onError(-1, "SDK session transition in progress"); return; }
        sessionOperation = true;
        clearSession(); // immediately invalidate notification work, even if network logout fails
        core.logout(new Base() {
            @Override public void onError(int code, String error) {
                synchronized (NativeIMRuntime.this) { sessionOperation = false; }
                callback.onError(code, error);
            }
            @Override public void onSuccess(String value) {
                synchronized (NativeIMRuntime.this) { sessionOperation = false; }
                callback.onSuccess(value);
            }
        }, operationID);
    }
    private void clearSession() {
        account = ""; token = ""; syncSnapshot = null; connectionSnapshot = null;
        final long cleared = ++sessionGeneration;
        post.accept(() -> { if (cleared == sessionGeneration) emitLocal("onSessionCleared"); });
    }
    public synchronized void setMessageListenerID(String id) { messageListenerID = id; messages.setListenerID(id); }
    public void readConversation(int type, String source, Base callback) {
        core.getOneConversation(callback, "native-notification", type, source);
    }
    public void readSelf(Base callback) { core.getSelfUserInfo(callback, "native-notification-self"); }
    public void replaySync() { post.accept(() -> { if (syncSnapshot != null) forwardFlutter("conversationListener", syncSnapshot); }); }
    private void replayConnection() { post.accept(() -> { if (connectionSnapshot != null) forwardFlutter("connectListener", connectionSnapshot); }); }
    private void emitLocal(String type) {
        Map<String, Object> data = new HashMap<>(); data.put("type", type); data.put("accountID", account);
        for (EventSink sink : nativeSinks) safe(sink, "nativeRuntime", data);
    }
    /** Invoked on Android main thread; native consumers never depend on Flutter. */
    public void emit(String method, Map<String, Object> event) { emit(method, event, sessionGeneration); }
    public void emit(String method, Map<String, Object> event, long expectedSession) {
        if (expectedSession != sessionGeneration) return;
        String type = String.valueOf(event.get("type"));
        if ("connectListener".equals(method)) {
            connectionSnapshot = new HashMap<>(event);
            if ("onKickedOffline".equals(type) || "onUserTokenExpired".equals(type) || "onUserTokenInvalid".equals(type)) {
                synchronized (this) { clearSession(); }
            }
        }
        if (!account.isEmpty() && "conversationListener".equals(method) && ("onSyncServerFinish".equals(type)
                || "onSyncServerStart".equals(type) || "onSyncServerFailed".equals(type))) syncSnapshot = new HashMap<>(event);
        for (EventSink sink : nativeSinks) safe(sink, method, event);
        forwardFlutter(method, event);
    }
    private void forwardFlutter(String method, Map<String, Object> event) {
        for (EventSink sink : flutterSinks) safe(sink, method, event);
    }
    private void safe(EventSink sink, String method, Map<String, Object> event) {
        try { sink.onEvent(method, event); }
        catch (RuntimeException error) { diagnostic.accept("Event consumer failed: " + error.getClass().getSimpleName()); }
    }
}
