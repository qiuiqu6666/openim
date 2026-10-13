package io.openim.gameshield;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Engine-local bridge; the process runtime alone owns the proxy and monitors. */
public final class GameShieldBridgePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private boolean attached;
    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        attached = true;
        GameShieldRuntime.INSTANCE.attach(binding.getApplicationContext());
        channel = new MethodChannel(binding.getBinaryMessenger(), "openim/gameshield");
        channel.setMethodCallHandler(this);
    }
    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        GameShieldRuntime.INSTANCE.onMethodCall(call, new MethodChannel.Result() {
            @Override public void success(Object value) { if (attached) result.success(value); }
            @Override public void error(String code, String message, Object details) { if (attached) result.error(code, message, details); }
            @Override public void notImplemented() { if (attached) result.notImplemented(); }
        });
    }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        attached = false;
        channel.setMethodCallHandler(null);
        channel = null;
    }
}
