package io.openim.flutter_openim_sdk;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import java.lang.reflect.Field;
import java.util.Collections;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import org.junit.Test;

/** Tests the current SDK dispatch/error and engine-lifetime callback contract. */
public class FlutterOpenimSdkPluginTest {
  private static final class DeferredPlugin extends FlutterOpenimSdkPlugin {
    MethodChannel.Result pending;
    @Override void parse(MethodCall call, MethodChannel.Result result) {
      pending = result;
    }
  }

  private static void attachChannel(FlutterOpenimSdkPlugin plugin, MethodChannel channel)
      throws Exception {
    Field field = FlutterOpenimSdkPlugin.class.getDeclaredField("engineChannel");
    field.setAccessible(true);
    field.set(plugin, channel);
  }

  private static MethodCall request() {
    return new MethodCall("getLoginStatus",
        Collections.singletonMap("ManagerName", "imManager"));
  }

  @Test public void activeEngineReceivesSdkSuccess() throws Exception {
    DeferredPlugin plugin = new DeferredPlugin();
    attachChannel(plugin, mock(MethodChannel.class));
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    plugin.onMethodCall(request(), result);
    plugin.pending.success("loggedIn");
    verify(result).success("loggedIn");
  }

  @Test public void activeEngineReceivesSdkError() throws Exception {
    DeferredPlugin plugin = new DeferredPlugin();
    attachChannel(plugin, mock(MethodChannel.class));
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    plugin.onMethodCall(request(), result);
    plugin.pending.error("10001", "disconnected", null);
    verify(result).error("10001", "disconnected", null);
  }

  @Test public void detachedEngineDoesNotReceiveLateSdkCallback() throws Exception {
    DeferredPlugin plugin = new DeferredPlugin();
    attachChannel(plugin, mock(MethodChannel.class));
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    plugin.onMethodCall(request(), result);
    attachChannel(plugin, null);
    plugin.pending.success("late");
    plugin.pending.error("10001", "late", null);
    plugin.pending.notImplemented();
    verifyNoInteractions(result);
  }

  @Test public void replacementEngineDoesNotReceivePreviousCallback() throws Exception {
    DeferredPlugin plugin = new DeferredPlugin();
    attachChannel(plugin, mock(MethodChannel.class));
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    plugin.onMethodCall(request(), result);
    attachChannel(plugin, mock(MethodChannel.class));
    plugin.pending.success("old session");
    verifyNoInteractions(result);
  }

  @Test public void unsupportedDispatchReturnsStructuredError() {
    // JVM tests have no Android Log implementation; keep the actual dispatch
    // and structured-error behavior under test.
    try (org.mockito.MockedStatic<android.util.Log> logs =
        org.mockito.Mockito.mockStatic(android.util.Log.class)) {
    FlutterOpenimSdkPlugin plugin = new FlutterOpenimSdkPlugin();
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    plugin.parse(new MethodCall("missingMethod",
        Collections.singletonMap("ManagerName", "missingManager")), result);
    verify(result).error("native_dispatch_error",
        "Chat native method dispatch failed: missingMethod", null);
    }
  }
}
