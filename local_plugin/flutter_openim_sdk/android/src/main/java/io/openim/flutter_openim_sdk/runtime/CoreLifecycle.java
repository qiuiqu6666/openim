package io.openim.flutter_openim_sdk.runtime;

import open_im_sdk_callback.Base;
import open_im_sdk_callback.OnConnListener;
import open_im_sdk_callback.OnAdvancedMsgListener;

/** Small native lifecycle boundary; business SDK methods remain unchanged. */
interface CoreLifecycle {
    boolean initSDK(OnConnListener listener, String operation, String config);
    void setAdvancedMsgListener(OnAdvancedMsgListener listener);
    String getSdkVersion();
    void unInitSDK(String operation);
    long getLoginStatus(String operation);
    void login(Base callback, String operation, String user, String token);
    void logout(Base callback, String operation);
    void getOneConversation(Base callback, String operation, int type, String source);
    void getSelfUserInfo(Base callback, String operation);
}
