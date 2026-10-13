package io.openim.flutter_openim_sdk.listener;

import android.util.ArrayMap;

import java.util.Map;

import io.openim.flutter_openim_sdk.util.CommonUtil;

public class OnAdvancedMsgListener implements open_im_sdk_callback.OnAdvancedMsgListener {
    private volatile String id;
    private final long generation;

    public void setListenerID(String value) { id = value; }

    public OnAdvancedMsgListener(String listenerId, long generation) {
        this.id = listenerId;
        this.generation = generation;
    }
    private void emit(String method, String type, Object value) {
        CommonUtil.emitEventForSession(method, type, null, null, value, generation);
    }

    @Override
    public void onMsgDeleted(String s) {
        final Map<String, String> values = new ArrayMap<>();
        values.put("id", id);
        values.put("message", s);
        emit("advancedMsgListener", "onMsgDeleted", values);
    }

    @Override
    public void onNewRecvMessageRevoked(String s) {
        final Map<String, String> values = new ArrayMap<>();
        values.put("id", id);
        values.put("messageRevoked", s);
        emit("advancedMsgListener", "onNewRecvMessageRevoked", values);
    }

    @Override
    public void onRecvC2CReadReceipt(String s) {
        final Map<String, String> values = new ArrayMap<>();
        values.put("id", id);
        values.put("msgReceiptList", s);
        emit("advancedMsgListener", "onRecvC2CReadReceipt", values);
    }

    @Override
    public void onRecvNewMessage(String s) {
        final Map<String, String> values = new ArrayMap<>();
        values.put("id", id);
        values.put("message", s);
        emit("advancedMsgListener", "onRecvNewMessage", values);
    }

    @Override
    public void onRecvOfflineNewMessage(String s) {
        final Map<String, String> values = new ArrayMap<>();
        values.put("id", id);
        values.put("message", s);
        emit("advancedMsgListener", "onRecvOfflineNewMessage", values);
    }

    @Override
    public void onRecvOnlineOnlyMessage(String s) {
        final Map<String, String> values = new ArrayMap<>();
        values.put("id", id);
        values.put("message", s);
        emit("advancedMsgListener", "onRecvOnlineOnlyMessage", values);
    }
}
