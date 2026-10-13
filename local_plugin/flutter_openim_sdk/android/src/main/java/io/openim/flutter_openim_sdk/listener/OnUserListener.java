package io.openim.flutter_openim_sdk.listener;

import io.openim.flutter_openim_sdk.util.CommonUtil;

public class OnUserListener implements open_im_sdk_callback.OnUserListener {

    @Override
    public void onUserCommandAdd(String command) {
        CommonUtil.emitEvent("userListener", "onUserCommandAdd", command);
    }

    @Override
    public void onUserCommandDelete(String command) {
        CommonUtil.emitEvent("userListener", "onUserCommandDelete", command);
    }

    @Override
    public void onUserCommandUpdate(String command) {
        CommonUtil.emitEvent("userListener", "onUserCommandUpdate", command);
    }

    @Override
    public void onSelfInfoUpdated(String s) {
        CommonUtil.emitEvent("userListener", "onSelfInfoUpdated", s);
    }

    @Override
    public void onUserStatusChanged(String s) {
        CommonUtil.emitEvent("userListener", "onUserStatusChanged", s);
    }
}
