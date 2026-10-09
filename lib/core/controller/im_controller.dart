import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:openim_live/openim_live.dart';

import '../im_callback.dart';
import '../notifications/legacy_notification_preferences.dart';
import '../notifications/message_notification_preferences.dart';
import '../session/sdk_session_queue.dart';
import '../user_activity/activity_runtime.dart';
import '../../services/account_privilege/account_privilege_runtime.dart';
import '../session/session_request_errors.dart';
import '../device_sync/device_sync_runtime.dart';
import '../../services/favorite_runtime.dart';
import '../../pages/mine/secondary/calls/data/call_records_runtime.dart';
import '../../pages/chat/calling/preferences/call_notification_preferences.dart';
import '../../pages/chat/calling/preferences/call_notification_preference_binding.dart';
import 'app_controller.dart';

class IMController extends GetxController with IMCallback, OpenIMLive {
  IMController({Duration loginStartTimeout = const Duration(seconds: 15)})
      : _loginStartTimeout = loginStartTimeout;
  final Duration _loginStartTimeout;
  final _sessionQueue = SdkSessionQueue();
  late Rx<UserFullInfo> userInfo;
  bool _hasUserInfo = false;
  int? _profileSessionGeneration;
  int? _notificationProfileGeneration;
  (String, String?, String)? _notificationProfileSession;
  final _legacyNotificationSeeder = LegacyNotificationPreferenceSeeder();
  bool get notificationPreferencesReady =>
      _profileSessionGeneration != null &&
      _notificationProfileGeneration == _profileSessionGeneration &&
      _notificationProfileSession ==
          (OpenIM.iMManager.userID, DataSp.chatToken, Config.appAuthUrl);

  bool _privilegeListenerAttached = false;
  late String atAllTag;
  late final _callPreferencesBinding = CallNotificationPreferenceBinding(
    currentAccount: () => OpenIM.iMManager.userID,
    refresh: refreshIncomingCallPreferences,
  );

  @override
  IncomingCallPreferences preferencesForIncomingCall(String accountID) =>
      CallNotificationPreferences.read(accountID);

  @override
  void onCallWaitingStarted() {
    if (Get.isRegistered<AppController>()) {
      unawaited(Get.find<AppController>().stopForegroundMessageAlerts());
    }
  }

  @override
  void onClose() {
    if (_privilegeListenerAttached) {
      AccountPrivilegeRuntime.store.removeListener(_syncAccountPrivilege);
      _privilegeListenerAttached = false;
    }
    _callPreferencesBinding.close();
    if (!Get.isRegistered<IMController>() ||
        identical(Get.find<IMController>(), this)) {
      DeviceSyncRuntime.instance.resetSession();
      ActivityRuntime.instance.resetConnection();
      AccountPrivilegeRuntime.store.reset();
    }
    _profileSessionGeneration = null;
    _notificationProfileGeneration = null;
    _notificationProfileSession = null;
    if (_hasUserInfo) userInfo.update((val) => val?.isPrivileged = false);
    final closingCallRecords = CallRecordsRuntime.currentRepository;
    FavoriteRuntime.detachSync();
    CallRecordsRuntime.detachSync();
    _sessionQueue.close();
    super.close();
    unawaited(onCloseLive().catchError((Object error, StackTrace _) {
      Logger.print('Call controller cleanup failed: ${error.runtimeType}');
    }).whenComplete(() {
      if (closingCallRecords != null) {
        CallRecordsRuntime.resetSession(expected: closingCallRecords);
      }
    }));
    super.onClose();
  }

  @override
  void onInit() async {
    super.onInit();
    onCallRecord = (record, accountID) async {
      if (Get.isRegistered<CacheController>()) {
        await CallRecordsRuntime.repository
            .recordCall(record, accountID: accountID);
      }
    };
    onInitLive();
    _callPreferencesBinding.attach();
    if (Get.isRegistered<AppController>()) {
      backgroundSubject.add(Get.find<AppController>().isRunningBackground);
    }
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
          ActivityRuntime.instance.connectionChanged(connected: false);
          imSdkStatus(IMSdkStatus.connecting);
        },
        onConnectFailed: (code, error) {
          ActivityRuntime.instance.connectionChanged(connected: false);
          imSdkStatus(IMSdkStatus.connectionFailed);
          if (code == 1506) userTokenInvalid();
        },
        onConnectSuccess: () {
          ActivityRuntime.instance.connectionChanged(connected: true);
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
        onMsgDeleted: messageDeleted,
        onRecvC2CReadReceipt: recvC2CMessageReadReceipt,
        onRecvNewMessage: recvNewMessage,
        onNewRecvMessageRevoked: recvMessageRevoked,
        onRecvOfflineNewMessage: recvOfflineMessage,
        onRecvOnlineOnlyMessage: (msg) {
          if (msg.contentType == MessageType.custom &&
              msg.customElem?.description == 'assistantStream') {
            // Stream deltas are transient SDK data, never business notices.
            onRecvNewMessage?.call(msg);
            return;
          }
          if (msg.contentType == MessageType.typing) {
            // Online-only input hints belong to the open SDK conversation;
            // never turn them into persisted messages or business notices.
            onRecvNewMessage?.call(msg);
            return;
          }
          if (msg.isCustomType) {
            final decoded = decodeCallSignal(msg);
            if (decoded != null) {
              final signaling = decoded.info;
              switch (decoded.customType) {
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
    if (initialized) {
      FavoriteRuntime.bindSync(
        businessNotifications: customBusinessMessageSubject.stream,
        reconnected: imSdkStatusPublishSubject
            .where((event) =>
                event.status == IMSdkStatus.connectionSucceeded ||
                event.status == IMSdkStatus.syncEnded)
            .map<void>((_) {}),
      );
      CallRecordsRuntime.bindSync(
        businessNotifications: customBusinessMessageSubject.stream,
        reconnected: imSdkStatusPublishSubject
            .where((event) =>
                event.status == IMSdkStatus.connectionSucceeded ||
                event.status == IMSdkStatus.syncEnded)
            .map<void>((_) {}),
      );
    }
    initializedSubject.sink.add(initialized);
  }

  Future login(String userID, String token) async {
    AccountPrivilegeRuntime.store.reset();
    _profileSessionGeneration = null;
    _notificationProfileGeneration = null;
    _notificationProfileSession = null;
    if (_hasUserInfo) userInfo.update((val) => val?.isPrivileged = false);
    int? generation;
    final credentialToken = DataSp.chatToken;
    try {
      final pending = _sessionQueue.login(
          () async {
            ActivityRuntime.instance.beginConnection(userID, token);
            final user = await OpenIM.iMManager.login(
              userID: userID,
              token: token,
              defaultValue: () async => UserInfo(userID: userID),
            );
            if (user.userID != userID) throw SdkSessionCancelled();
            return user;
          },
          startTimeout: _loginStartTimeout,
          prepare: () async {
            // Include retrying a failed native cleanup in the preparation deadline.
            // The SDK otherwise reuses an already logged-in native session.
            if (OpenIM.iMManager.isLogined &&
                (OpenIM.iMManager.userID != userID ||
                    OpenIM.iMManager.token != token)) {
              await _logoutSafely();
            }
          });
      generation = _sessionQueue.generation;
      final user = await pending;
      if (!_sessionQueue.isCurrent(generation) || isClosed) {
        throw SdkSessionCancelled();
      }
      userInfo =
          (UserFullInfo.fromJson(user.toJson())..isPrivileged = false).obs;
      _hasUserInfo = true;
      _profileSessionGeneration = generation;
      if (!_privilegeListenerAttached) {
        AccountPrivilegeRuntime.store.addListener(_syncAccountPrivilege);
        _privilegeListenerAttached = true;
      }
      _syncAccountPrivilege();
      unawaited(refreshMyFullInfo());
      _queryAtAllTag();
    } catch (e, s) {
      Logger.print('OpenIM login failed');
      if (generation != null && _sessionQueue.isCurrent(generation)) {
        await _handleLoginRepeatError(e,
            account: userID, imToken: token, credentialToken: credentialToken);
      }

      return Future.error(e, s);
    }
  }

  Future<void>? _pendingLogout;

  Future<void> logout() {
    ActivityRuntime.instance.resetConnection();
    AccountPrivilegeRuntime.store.reset();
    _profileSessionGeneration = null;
    _notificationProfileGeneration = null;
    _notificationProfileSession = null;
    if (_hasUserInfo) userInfo.update((val) => val?.isPrivileged = false);
    DeviceSyncRuntime.instance.resetSession();
    initLogic.clearMessageNotificationSession();
    FavoriteRuntime.resetSession();
    final pending = _pendingLogout;
    if (pending != null) {
      _sessionQueue.invalidate();
      return pending;
    }
    return _pendingLogout = _sessionQueue
        .logout(_logoutSafely)
        .whenComplete(() => _pendingLogout = null);
  }

  Future<void> _logoutSafely() async {
    // Login preparation can call this directly when replacing a native account.
    DeviceSyncRuntime.instance.resetSession();
    // End media/signaling while the old SDK account still owns the call.
    // The session queue prevents a new account from logging in during cleanup.
    try {
      await endLiveSession();
    } finally {
      CallRecordsRuntime.resetSession();
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

  /// Login, foreground and feature entries share the authenticated full profile.
  Future<bool> refreshMyFullInfo() async {
    final generation = _profileSessionGeneration;
    if (isClosed ||
        !_hasUserInfo ||
        generation == null ||
        !_sessionQueue.isCurrent(generation)) {
      return false;
    }
    final target = userInfo;
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    final base = Config.appAuthUrl;
    if (account.isEmpty ||
        target.value.userID != account ||
        DataSp.userID != account ||
        token?.isNotEmpty != true ||
        !OpenIM.iMManager.isLogined) {
      target.update((val) => val?.isPrivileged = false);
      return false;
    }
    bool current() =>
        !isClosed &&
        _sessionQueue.isCurrent(generation) &&
        _profileSessionGeneration == generation &&
        identical(target, userInfo) &&
        account == OpenIM.iMManager.userID &&
        DataSp.userID == account &&
        OpenIM.iMManager.isLogined &&
        token == DataSp.chatToken &&
        base == Config.appAuthUrl;
    try {
      final data = await AccountPrivilegeRuntime.store.refreshProfile();
      if (!current()) return false;
      if (data != null && data.userID == account) {
        final ready = await _legacyNotificationSeeder.apply(
            owner: account,
            snapshot: data.legacyNotificationSnapshot,
            isCurrent: current);
        if (!current() || !ready) return false;
        _notificationProfileGeneration = generation;
        _notificationProfileSession = (account, token, base);
        MessageNotificationPreferences.notifyChanged(account);
        target.update((val) {
          val?.account = data.account;
          val?.allowAddFriend = data.allowAddFriend;
          val?.allowBeep = data.allowBeep;
          val?.allowVibration = data.allowVibration;
          val?.nickname = data.nickname;
          val?.faceURL = data.faceURL;
          val?.phoneNumber = data.phoneNumber;
          val?.email = data.email;
          val?.birth = data.birth;
          val?.gender = data.gender;
          val?.isPrivileged = data.isPrivileged;
        });
        return true;
      }
      target.update((val) => val?.isPrivileged = false);
      final error = AccountPrivilegeRuntime.store.lastError;
      if (error != null) {
        handleSessionAuthFailure(error, account: account, token: token);
      }
    } catch (error) {
      if (current()) {
        target.update((val) => val?.isPrivileged = false);
        handleSessionAuthFailure(error, account: account, token: token);
      }
      // A background profile refresh must not fail an already successful login.
      Logger.print('Profile refresh failed: $error');
    }
    return false;
  }

  void _syncAccountPrivilege() {
    final generation = _profileSessionGeneration;
    if (isClosed ||
        !_hasUserInfo ||
        generation == null ||
        !_sessionQueue.isCurrent(generation)) {
      return;
    }
    final target = userInfo;
    final account = OpenIM.iMManager.userID;
    if (account.isEmpty || target.value.userID != account) return;
    final allowed = OpenIM.iMManager.isLogined &&
        AccountPrivilegeRuntime.store
            .allows(userID: account, baseUrl: Config.appAuthUrl);
    if (target.value.isPrivileged != allowed) {
      target.update((val) => val?.isPrivileged = allowed);
    }
  }

  Future<void> _handleLoginRepeatError(Object e,
      {required String account,
      required String imToken,
      required String? credentialToken}) async {
    if (e is PlatformException && (e.code == "13002" || e.code == '1507')) {
      final cleanup = logout();
      unawaited(cleanup.catchError((Object error, StackTrace _) {
        Logger.print('SDK repeat-login cleanup failed: $error');
      }));
      final cleanupGeneration = _sessionQueue.generation;
      if (_sessionQueue.isCurrent(cleanupGeneration) &&
          account == DataSp.userID &&
          imToken == DataSp.imToken &&
          credentialToken == DataSp.chatToken) {
        await DataSp.removeLoginCertificate();
      }
    }
  }
}
