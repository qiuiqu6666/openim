package io.openim.flutter_openim_sdk.manager;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.openim.flutter_openim_sdk.FlutterOpenimSdkPlugin;
import io.openim.flutter_openim_sdk.listener.OnBaseListener;
import io.openim.flutter_openim_sdk.listener.OnConnListener;
import io.openim.flutter_openim_sdk.listener.OnUploadFileListener;
import io.openim.flutter_openim_sdk.listener.OnUploadLogsListener;
import io.openim.flutter_openim_sdk.util.CommonUtil;
import open_im_sdk.Open_im_sdk;

public class IMManager extends BaseManager {

    public void initSDK(MethodCall methodCall, MethodChannel.Result result) {
        android.util.Log.i("ChatCore", "Native Core version: " + Open_im_sdk.getSdkVersion());
        boolean initialized = io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().initialize(
                value(methodCall, "operationID"),
                jsonValue(methodCall));
        FlutterOpenimSdkPlugin.isInitialized = initialized;
        CommonUtil.runMainThreadReturn(result, initialized);
    }

    public void unInitSDK(MethodCall methodCall, MethodChannel.Result result) {
        io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().shutdown(value(methodCall, "operationID"));
        FlutterOpenimSdkPlugin.isInitialized = false;
        CommonUtil.runMainThreadReturn(result, null);
    }

    public void login(MethodCall methodCall, MethodChannel.Result result) {
        io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().login(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID"),
                value(methodCall, "userID"),
                value(methodCall, "token")
        );
    }

    public void logout(MethodCall methodCall, MethodChannel.Result result) {
        io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().logout(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID")
        );
    }

    public void getLoginStatus(MethodCall methodCall, MethodChannel.Result result) {
        CommonUtil.runMainThreadReturn(result, io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().loginStatus(value(methodCall, "operationID")));
    }
    public void cancelLogin(MethodCall methodCall, MethodChannel.Result result) {
        io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().cancelLogin(
            new OnBaseListener(result, methodCall), value(methodCall, "operationID"), value(methodCall, "targetOperationID"));
    }

    public void uploadFile(MethodCall methodCall, MethodChannel.Result result) {
        Open_im_sdk.uploadFile(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID"),
                jsonValue(methodCall),
                new OnUploadFileListener(result, methodCall)
        );
    }

    public void updateFcmToken(MethodCall methodCall, MethodChannel.Result result) {
        Open_im_sdk.updateFcmToken(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID"),
                value(methodCall, "fcmToken"),
                int2long(methodCall, "expireTime")
        );
    }

    public void uploadLogs(MethodCall methodCall, MethodChannel.Result result) {
        Open_im_sdk.uploadLogs(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID"),
                int2long(methodCall, "line"),
                value(methodCall, "ex"),
                new OnUploadLogsListener(result, methodCall)
        );
    }

    public void logs(MethodCall methodCall, MethodChannel.Result result) {
        Open_im_sdk.logs(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID"),
                int2long(methodCall, "logLevel"),
                value(methodCall, "file"),
                int2long(methodCall, "line"),
                value(methodCall, "msgs"),
                value(methodCall, "err"),
                value(methodCall, "keyAndValue")
        );
    }

    public void setDiagnosticLogging(MethodCall call, MethodChannel.Result result) {
        Number seconds = call.argument("seconds");
        if (seconds == null) {
            result.error("invalid_arguments", "seconds is required", null);
            return;
        }
        CommonUtil.runMainThreadReturn(result,
                Open_im_sdk.setDiagnosticLogging(Math.max(0, Math.min(900, seconds.longValue()))));
    }

    public void getDiagnosticLoggingSeconds(MethodCall call, MethodChannel.Result result) {
        CommonUtil.runMainThreadReturn(result, Open_im_sdk.getDiagnosticLoggingSeconds());
    }

    public void setAppBackgroundStatus(MethodCall methodCall, MethodChannel.Result result) {
        Open_im_sdk.setAppBackgroundStatus(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID"),
                value(methodCall, "isBackground")
        );
    }


    public void networkStatusChanged(MethodCall methodCall, MethodChannel.Result result) {
        Open_im_sdk.networkStatusChanged(
                new OnBaseListener(result, methodCall),
                value(methodCall, "operationID")
        );
    }

//    public void setListenerForService(MethodCall methodCall, MethodChannel.Result result) {
//        Open_im_sdk.setListenerForService(new OnListenerForService());
//
//        result.success(null);
//    }

}
