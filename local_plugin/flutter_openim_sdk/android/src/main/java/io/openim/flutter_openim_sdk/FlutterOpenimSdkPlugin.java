package io.openim.flutter_openim_sdk;

import android.app.Activity;
import android.content.Context;

import androidx.annotation.NonNull;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.openim.flutter_openim_sdk.connectivity.ConnectivityListener;
import io.openim.flutter_openim_sdk.connectivity.VisibilityListener;
import io.openim.flutter_openim_sdk.manager.ConversationManager;
import io.openim.flutter_openim_sdk.manager.FriendshipManager;
import io.openim.flutter_openim_sdk.manager.GroupManager;
import io.openim.flutter_openim_sdk.manager.IMManager;
import io.openim.flutter_openim_sdk.manager.MessageManager;
import io.openim.flutter_openim_sdk.manager.UserManager;


/**
 * FlutterOpenimSdkPlugin
 */
public class FlutterOpenimSdkPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private static final String CHANNEL_NAME = "flutter_openim_sdk";
    public static MethodChannel channel;
    private static IMManager imManager;
    private static UserManager userManager;
    private static FriendshipManager friendshipManager;
    private static MessageManager messageManager;
    private static ConversationManager conversationManager;
    private static GroupManager groupManager;
    private static Activity activity;
    private static Context context;
    private MethodChannel engineChannel;
    private io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.EventSink eventSink;
    public static boolean isInitialized;

    public FlutterOpenimSdkPlugin() {
        FlutterOpenimSdkPlugin.imManager = new IMManager();
        FlutterOpenimSdkPlugin.userManager = new UserManager();
        FlutterOpenimSdkPlugin.friendshipManager = new FriendshipManager();
        FlutterOpenimSdkPlugin.messageManager = new MessageManager();
        FlutterOpenimSdkPlugin.conversationManager = new ConversationManager();
        FlutterOpenimSdkPlugin.groupManager = new GroupManager();
    }


    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL_NAME);
        context = flutterPluginBinding.getApplicationContext();
        channel.setMethodCallHandler(this);
        engineChannel = channel;
        eventSink = (method, event) -> engineChannel.invokeMethod(method, event);
        io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().attachApplication(context);
        io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().attachFlutter(eventSink);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        final MethodChannel origin = engineChannel;
        parse(call, new Result() {
            @Override public void success(Object value) { if (origin != null && engineChannel == origin) result.success(value); }
            @Override public void error(String code, String message, Object details) { if (origin != null && engineChannel == origin) result.error(code, message, details); }
            @Override public void notImplemented() { if (origin != null && engineChannel == origin) result.notImplemented(); }
        });
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().detachFlutter(eventSink);
        engineChannel.setMethodCallHandler(null);
        if (channel == engineChannel) channel = null;
        engineChannel = null;
    }


    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

    void parse(@NonNull MethodCall call, @NonNull Result result) {
        try {
            String managerName = call.argument("ManagerName");
            Field field = FlutterOpenimSdkPlugin.class.getDeclaredField(managerName);
            Method method = field.get(new Object()).getClass().getDeclaredMethod(call.method, MethodCall.class, Result.class);
            io.openim.flutter_openim_sdk.util.DiagnosticLog.detail("ChatSDK(flutter call native)", "{ class:" + managerName + ",  method:" + method.getName() + " }");
            method.invoke(field.get(new Object()), call, result);
        } catch (Exception e) {
            io.openim.flutter_openim_sdk.util.DiagnosticLog.error(android.util.Log.getStackTraceString(e));
            result.error("native_dispatch_error", "Chat native method dispatch failed: " + call.method, null);
        }
    }
}
