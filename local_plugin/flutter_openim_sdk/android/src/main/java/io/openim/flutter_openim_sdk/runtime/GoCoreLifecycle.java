package io.openim.flutter_openim_sdk.runtime;

import open_im_sdk.Open_im_sdk;
import open_im_sdk_callback.Base;
import open_im_sdk_callback.OnConnListener;
import open_im_sdk_callback.OnAdvancedMsgListener;

/** Production implementation calls the existing patched Go AAR, never an emulation. */
final class GoCoreLifecycle implements CoreLifecycle {
    public boolean initSDK(OnConnListener listener, String operation, String config) { return Open_im_sdk.initSDK(listener, operation, config); }
    public void setAdvancedMsgListener(OnAdvancedMsgListener listener) { Open_im_sdk.setAdvancedMsgListener(listener); }
    public String getSdkVersion() { return Open_im_sdk.getSdkVersion(); }
    public void unInitSDK(String operation) { Open_im_sdk.unInitSDK(operation); }
    public long getLoginStatus(String operation) { return Open_im_sdk.getLoginStatus(operation); }
    public void login(Base callback, String operation, String user, String token) { Open_im_sdk.login(callback, operation, user, token); }
    public void logout(Base callback, String operation) { Open_im_sdk.logout(callback, operation); }
    public void getOneConversation(Base callback, String operation, int type, String source) { Open_im_sdk.getOneConversation(callback, operation, type, source); }
    public void getSelfUserInfo(Base callback, String operation) { Open_im_sdk.getSelfUserInfo(callback, operation); }
}
