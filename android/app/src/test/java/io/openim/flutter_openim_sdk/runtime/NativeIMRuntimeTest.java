package io.openim.flutter_openim_sdk.runtime;

import java.util.*;
import org.junit.Test;
import static org.junit.Assert.*;
import open_im_sdk_callback.*;

public class NativeIMRuntimeTest {
    private static final String CONFIG = "{\"platformID\":2,\"apiAddr\":\"https://api\",\"wsAddr\":\"wss://ws\",\"dataDir\":\"/app_flutter/\"}";
    private static final Base IGNORE = new Base() { public void onSuccess(String s) {} public void onError(int c, String e) {} };
    private final FakeCore core = new FakeCore();
    private final NativeIMRuntime runtime = new NativeIMRuntime(core, Runnable::run, value -> {});
    @Test public void repeatedInitAndEngineRecreationKeepOneNativeInstance() {
        assertTrue(runtime.initialize("first", CONFIG));
        NativeIMRuntime.EventSink engine = (method, value) -> {};
        runtime.attachFlutter(engine); runtime.detachFlutter(engine);
        assertTrue(runtime.initialize("second", CONFIG));
        assertEquals(1, core.initializations); assertEquals(0, core.shutdowns);
        assertTrue(runtime.isInitialized());
    }
    @Test public void changedDatabaseCannotImplicitlyReplaceLiveCore() {
        runtime.initialize("first", CONFIG);
        try { runtime.initialize("other", CONFIG.replace("/app_flutter/", "/different/")); fail(); }
        catch (IllegalStateException expected) {}
        assertEquals(1, core.initializations);
        runtime.shutdown("explicit");
        runtime.initialize("other", CONFIG.replace("/app_flutter/", "/different/"));
        assertEquals(2, core.initializations); assertEquals(1, core.shutdowns);
    }
    @Test public void nativeEventsContinueAfterEngineDetachAndDoNotReachOldEngine() {
        List<String> nativeEvents = new ArrayList<>(), oldEvents = new ArrayList<>(), newEvents = new ArrayList<>();
        NativeIMRuntime.EventSink old = (method, event) -> oldEvents.add(method);
        runtime.addNativeSink((method, event) -> nativeEvents.add(method)); runtime.attachFlutter(old);
        runtime.detachFlutter(old);
        runtime.emit("advancedMsgListener", Collections.singletonMap("type", "onRecvNewMessage"));
        assertEquals(Arrays.asList("nativeRuntime", "advancedMsgListener"), nativeEvents); assertTrue(oldEvents.isEmpty());
        runtime.attachFlutter((method, event) -> newEvents.add(method));
        runtime.emit("advancedMsgListener", Collections.singletonMap("type", "onRecvNewMessage"));
        assertEquals(Collections.singletonList("advancedMsgListener"), newEvents); assertTrue(oldEvents.isEmpty());
    }
    @Test public void engineLoginAttachesToSameAccountWithoutSecondLogin() {
        runtime.initialize("init", CONFIG); runtime.login(IGNORE, "login", "alice", "token");
        core.finishLogin(); runtime.login(IGNORE, "engine-recreated", "alice", "token");
        assertEquals(1, core.logins); assertEquals("alice", runtime.accountID());
    }
    @Test public void accountSwitchAndConcurrentLoginAreRejected() {
        runtime.initialize("init", CONFIG); runtime.login(IGNORE, "login", "alice", "token");
        List<Integer> failures = new ArrayList<>();
        Base callback = new Base() { public void onSuccess(String s) { fail(); } public void onError(int c, String e) { failures.add(c); } };
        runtime.login(callback, "parallel", "alice", "token"); core.finishLogin();
        runtime.login(callback, "other-user", "bob", "token");
        assertEquals(2, failures.size()); assertEquals(1, core.logins);
    }
    @Test public void logoutInvalidatesNativeSessionBeforeSdkCompletion() {
        runtime.initialize("init", CONFIG); runtime.login(IGNORE, "login", "alice", "token"); core.finishLogin();
        runtime.logout(IGNORE, "logout"); assertEquals("", runtime.accountID()); assertEquals(1, core.logouts);
        core.finishLogout(); runtime.login(IGNORE, "new", "bob", "token2"); core.finishLogin();
        assertEquals("bob", runtime.accountID());
    }
    @Test public void queuedOldAccountEventsAreDiscardedAfterAccountSwitch() {
        runtime.initialize("init", CONFIG); runtime.login(IGNORE, "login", "alice", "token"); core.finishLogin();
        long oldSession = runtime.sessionGeneration();
        runtime.logout(IGNORE, "logout"); core.finishLogout();
        runtime.login(IGNORE, "new", "bob", "token2"); core.finishLogin();
        List<String> received = new ArrayList<>(); runtime.addNativeSink((m,e) -> received.add(m));
        runtime.emit("advancedMsgListener", Collections.singletonMap("type", "onRecvNewMessage"), oldSession);
        assertTrue(received.isEmpty());
        runtime.emit("advancedMsgListener", Collections.singletonMap("type", "onRecvNewMessage"), runtime.sessionGeneration());
        assertEquals(Collections.singletonList("advancedMsgListener"), received);
    }
    @Test public void failingUiConsumerDoesNotStopNativeDelivery() {
        List<String> received = new ArrayList<>(); runtime.attachFlutter((m,e) -> { throw new IllegalStateException(); });
        runtime.addNativeSink((m,e) -> received.add(m));
        runtime.emit("advancedMsgListener", Collections.singletonMap("type", "onRecvNewMessage"));
        assertEquals(Collections.singletonList("advancedMsgListener"), received);
    }
    private static final class FakeCore implements CoreLifecycle {
        int initializations, shutdowns, logins, logouts, status;
        Base pendingLogin, pendingLogout;
        public boolean initSDK(OnConnListener l,String o,String c) { initializations++; return true; }
        public void setAdvancedMsgListener(OnAdvancedMsgListener l) {}
        public String getSdkVersion() { return "test"; }
        public void unInitSDK(String o) { shutdowns++; status=0; }
        public long getLoginStatus(String o) { return status; }
        public void login(Base cb,String o,String u,String t) { logins++; status=2; pendingLogin=cb; }
        public void logout(Base cb,String o) { logouts++; pendingLogout=cb; }
        void finishLogin() { status=3; pendingLogin.onSuccess(""); }
        void finishLogout() { status=1; pendingLogout.onSuccess(""); }
        public void getOneConversation(Base cb,String o,int t,String s) { throw new UnsupportedOperationException(); }
        public void getSelfUserInfo(Base cb,String o) { throw new UnsupportedOperationException(); }
    }
}
