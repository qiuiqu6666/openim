import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:openim_live/openim_live.dart';

import '../im_callback.dart';

class IMController extends GetxController with IMCallback, OpenIMLive {
  late Rx<UserFullInfo> userInfo;
  late String atAllTag;

  @override
  void onClose() {
    super.close();
    onCloseLive();
    super.onClose();
  }

  @override
  void onInit() async {
    super.onInit();
    onInitLive();
    WidgetsBinding.instance.addPostFrameCallback((_) => initOpenIM());
  }

  void initOpenIM() async {
    final initialized = await OpenIM.iMManager.initSDK(
      platformID: IMUtils.getPlatform(),
      apiAddr: Config.imApiUrl,
      wsAddr: Config.imWsUrl,
      dataDir: Config.cachePath,
      logLevel: Config.logLevel,
      logFilePath: Config.cachePath,
      listener: OnConnectListener(
        onConnecting: () {
          imSdkStatus(IMSdkStatus.connecting);
        },
        onConnectFailed: (code, error) {
          imSdkStatus(IMSdkStatus.connectionFailed);
        },
        onConnectSuccess: () {
          imSdkStatus(IMSdkStatus.connectionSucceeded);
        },
        onKickedOffline: kickedOffline,
        onUserTokenExpired: kickedOffline,
        onUserTokenInvalid: userTokenInvalid,
      ),
    );

    OpenIM.iMManager
      ..setUploadLogsListener(
          OnUploadLogsListener(onUploadProgress: uploadLogsProgress))
      ..userManager.setUserListener(OnUserListener(
          onSelfInfoUpdated: (u) {
            selfInfoUpdated(u);

            userInfo.update((val) {
              val?.nickname = u.nickname;
              val?.faceURL = u.faceURL;

              val?.remark = u.remark;
              val?.ex = u.ex;
              val?.globalRecvMsgOpt = u.globalRecvMsgOpt;
            });
          },
          onUserStatusChanged: userStausChanged))
      ..messageManager.setAdvancedMsgListener(OnAdvancedMsgListener(
        onMsgDeleted: (message) => deletedMessages.addSafely(message),
        onRecvC2CReadReceipt: recvC2CMessageReadReceipt,
        onRecvNewMessage: recvNewMessage,
        onNewRecvMessageRevoked: recvMessageRevoked,
        onRecvOfflineNewMessage: recvOfflineMessage,
        onRecvOnlineOnlyMessage: (msg) {
          if (msg.isCustomType) {
            final data = msg.customElem!.data;
            final map = jsonDecode(data!);
            final customType = map['customType'];
            if (customType == CustomMessageType.callingInvite ||
                customType == CustomMessageType.callingAccept ||
                customType == CustomMessageType.callingReject ||
                customType == CustomMessageType.callingCancel ||
                customType == CustomMessageType.callingHungup) {
              final signaling = SignalingInfo(
                  invitation: InvitationInfo.fromJson(map['data']));
              signaling.userID = signaling.invitation?.inviterUserID;

              switch (customType) {
                case CustomMessageType.callingInvite:
                  receiveNewInvitation(signaling);
                  break;
                case CustomMessageType.callingAccept:
                  inviteeAccepted(signaling);
                  break;
                case CustomMessageType.callingReject:
                  inviteeRejected(signaling);
                  break;
                case CustomMessageType.callingCancel:
                  invitationCancelled(signaling);
                  break;
                case CustomMessageType.callingHungup:
                  beHangup(signaling);
                  break;
              }
            }
          }
        },
      ))
      ..messageManager.setMsgSendProgressListener(OnMsgSendProgressListener(
        onProgress: progressCallback,
      ))
      ..messageManager.setCustomBusinessListener(OnCustomBusinessListener(
        onRecvCustomBusinessMessage: recvCustomBusinessMessage,
      ))
      ..friendshipManager.setFriendshipListener(OnFriendshipListener(
        onBlackAdded: blacklistAdded,
        onBlackDeleted: blacklistDeleted,
        onFriendApplicationAccepted: friendApplicationAccepted,
        onFriendApplicationAdded: friendApplicationAdded,
        onFriendApplicationDeleted: friendApplicationDeleted,
        onFriendApplicationRejected: friendApplicationRejected,
        onFriendInfoChanged: friendInfoChanged,
        onFriendAdded: friendAdded,
        onFriendDeleted: friendDeleted,
      ))
      ..conversationManager.setConversationListener(OnConversationListener(
          onConversationChanged: conversationChanged,
          onNewConversation: newConversation,
          onTotalUnreadMessageCountChanged: totalUnreadMsgCountChanged,
          onInputStatusChanged: inputStateChanged,
          onSyncServerFailed: (reInstall) {
            imSdkStatus(IMSdkStatus.syncFailed, reInstall: reInstall ?? false);
          },
          onSyncServerFinish: (reInstall) {
            imSdkStatus(IMSdkStatus.syncEnded, reInstall: reInstall ?? false);
            if (Platform.isAndroid) {
              Permissions.request([Permission.systemAlertWindow]);
            }
          },
          onSyncServerStart: (reInstall) {
            imSdkStatus(IMSdkStatus.syncStart, reInstall: reInstall ?? false);
          },
          onSyncServerProgress: (progress) {
            imSdkStatus(IMSdkStatus.syncProgress, progress: progress);
          }))
      ..groupManager.setGroupListener(OnGroupListener(
        onGroupApplicationAccepted: groupApplicationAccepted,
        onGroupApplicationAdded: groupApplicationAdded,
        onGroupApplicationDeleted: groupApplicationDeleted,
        onGroupApplicationRejected: groupApplicationRejected,
        onGroupInfoChanged: groupInfoChanged,
        onGroupMemberAdded: groupMemberAdded,
        onGroupMemberDeleted: groupMemberDeleted,
        onGroupMemberInfoChanged: groupMemberInfoChanged,
        onJoinedGroupAdded: joinedGroupAdded,
        onJoinedGroupDeleted: joinedGroupDeleted,
      ));

    Logger().sdkIsInited = initialized;
    initializedSubject.sink.add(initialized);
  }

  Future login(String userID, String token) async {
    try {
      final pending = OpenIM.iMManager.login(
        userID: userID,
        token: token,
        defaultValue: () async => UserInfo(userID: userID),
      );
      _pendingSdkLogin = pending;
      final user = await pending;
      _pendingSdkLogin = null;
      userInfo = UserFullInfo.fromJson(user.toJson()).obs;
      _queryMyFullInfo();
      _queryAtAllTag();
    } catch (e, s) {
      _pendingSdkLogin = null;
      Logger.print('OpenIM login failed');
      await _handleLoginRepeatError(e);

      return Future.error(e, s);
    }
  }

  Future<UserInfo>? _pendingSdkLogin;
  Future<void>? _pendingLogout;

  Future<void> logout() {
    return _pendingLogout ??=
        _logoutSafely().whenComplete(() => _pendingLogout = null);
  }

  Future<void> _logoutSafely() async {
    final pending = _pendingSdkLogin;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {/* A failed login may already be logged out. */}
    }
    try {
      final status = await OpenIM.iMManager.getLoginStatus();
      if (status == LoginStatus.logout) return;
      await OpenIM.iMManager.logout();
    } on PlatformException catch (error) {
      // The SDK can finish disconnecting between the status check and logout.
      if (error.code != '10009') rethrow;
    }
  }

  void _queryAtAllTag() async {
    atAllTag = OpenIM.iMManager.conversationManager.atAllTag;
  }

  void _queryMyFullInfo() async {
    final data = await Apis.queryMyFullInfo();
    if (data is UserFullInfo) {
      userInfo.update((val) {
        val?.allowAddFriend = data.allowAddFriend;
        val?.allowBeep = data.allowBeep;
        val?.allowVibration = data.allowVibration;
        val?.nickname = data.nickname;
        val?.faceURL = data.faceURL;
        val?.phoneNumber = data.phoneNumber;
        val?.email = data.email;
        val?.birth = data.birth;
        val?.gender = data.gender;
      });
    }
  }

  _handleLoginRepeatError(e) async {
    if (e is PlatformException && (e.code == "13002" || e.code == '1507')) {
      await logout();
      await DataSp.removeLoginCertificate();
    }
  }
}
