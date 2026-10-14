import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

import '../im_callback.dart';
import '../session/message_events.dart';
import '../calling/data/call_signal_persistence.dart';
import '../calling/data/call_state_runtime.dart';
import '../notifications/legacy_notification_preferences.dart';
import '../notifications/message_notification_preferences.dart';
import '../session/sdk_session_queue.dart';
import '../session/connection/im_connection_recovery.dart';
import '../session/connection/api_connection_health.dart';
import '../session/connection/im_native_connection_wake.dart';
import '../user_activity/activity_runtime.dart';
import '../../services/account_privilege/account_privilege_runtime.dart';
import '../session/session_request_errors.dart';
import '../device_sync/device_sync_runtime.dart';
import '../../services/favorite_runtime.dart';
import '../../pages/ai_assistant/streaming/diagnostics/assistant_stream_log.dart';
import '../../pages/mine/secondary/calls/data/call_records_runtime.dart';
import '../../pages/chat/calling/preferences/call_notification_preferences.dart';
import '../../pages/chat/calling/preferences/call_notification_preference_binding.dart';
import 'app_controller.dart';

class IMController extends GetxController with IMCallback, OpenIMLive {
  IMController({Duration loginStartTimeout = const Duration(seconds: 15)})
      : _loginStartTimeout = loginStartTimeout;
  final Duration _loginStartTimeout;
  final _sessionQueue = SdkSessionQueue();
  IMConnectionRecovery? _connectionRecovery;
  ApiConnectionHealth? apiConnectionHealth;
  IMNativeConnectionWake? _nativeConnectionWake;
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
  Future<void> persistSignal(int type, InvitationInfo invitation) =>
      persistCallSignal(type, invitation);

  @override
  void onCallReleased(String roomID) =>
      CallStateRuntime.instance.release(roomID);

  @override
  void receiveNewInvitation(SignalingInfo info) {
    final invitation = info.invitation;
    if (invitation == null ||
        !validCallInvitation(invitation) ||
        info.userID != invitation.inviterUserID) return;
    final account = DataSp.userID, token = DataSp.chatToken;
    unawaited(
        CallStateRuntime.instance.admitIncoming(invitation).then((admitted) {
      if (admitted &&
          !isClosed &&
          DataSp.userID == account &&
          DataSp.chatToken == token) super.receiveNewInvitation(info);
    }).catchError((Object error) {
      Logger.print(
          'Incoming call verification unavailable: ${error.runtimeType}');
    }));
  }

  void _bindCallState() {
    final runtime = CallStateRuntime.instance;
    runtime.ready = () =>
        !isClosed &&
        currentSdkStatus == IMSdkStatus.syncEnded &&
        DataSp.userID == OpenIM.iMManager.userID;
    runtime.activeRoom = () => activeCallRoomID;
    runtime.restoreIncoming = (value) => restoreIncomingCall(
        SignalingInfo(
            userID: value.invitation.inviterUserID,
            invitation: value.invitation),
        callerName: value.callerName);
    runtime.onState = (value, deviceID) async {
      final account = DataSp.userID, token = DataSp.chatToken;
      if (account == null || account != OpenIM.iMManager.userID || isClosed)
        return;
      final elsewhere = value.answeredElsewhere(account, deviceID);
      final local = applyServerCallState(
          accountID: account,
          roomID: value.room,
          state: value.state,
          reason: value.reason,
          answeredElsewhere: elsewhere,
          verifiedInvitation: value.invitation);
      // Media must release its tracks before CallKit restores the audio session.
      await local;
      if (DataSp.userID != account || DataSp.chatToken != token || isClosed)
        return;
      if (value.terminal || elsewhere) {
        await initLogic.closeSystemCallFromServer(value.room,
            answeredElsewhere: elsewhere);
      } else if (value.state == 'accepted' &&
          value.participant(account, deviceID)) {
        await initLogic.systemCallAccepted(value.room);
      }
    };
    runtime.bind(
        business: customBusinessMessageSubject.stream,
        recovery: imSdkStatusPublishSubject
            .where((event) =>
                event.status == IMSdkStatus.connectionSucceeded ||
                event.status == IMSdkStatus.syncEnded)
            .map<void>((_) {}));
  }

  @override
  IncomingCallPreferences preferencesForIncomingCall(String accountID) =>
      CallNotificationPreferences.read(accountID);

  @override
  SystemCallAdapter? get systemCallAdapter => Get.isRegistered<AppController>()
      ? Get.find<AppController>().iosSystemCallAdapter
      : null;

  @override
  void onCallWaitingStarted() {
    if (Get.isRegistered<AppController>()) {
      unawaited(Get.find<AppController>().stopForegroundMessageAlerts());
    }
  }

  @override
  void onClose() {
    apiConnectionHealth?.close();
    apiConnectionHealth = null;
    _connectionRecovery?.close();
    _nativeConnectionWake?.close();
    if (_privilegeListenerAttached) {
      AccountPrivilegeRuntime.store.removeListener(_syncAccountPrivilege);
      _privilegeListenerAttached = false;
    }
    _callPreferencesBinding.close();
    if (!Get.isRegistered<IMController>() ||
        identical(Get.find<IMController>(), this)) {
      CallStateRuntime.instance.close();
      DeviceSyncRuntime.instance.resetSession();
      initLogic.clearBadgeSession();
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
    _bindCallState();
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

  Future<bool> initOpenIM({bool notifyStartup = true}) async {
    final initialized = await OpenIM.iMManager.initSDK(
      platformID: IMUtils.getPlatform(),
      apiAddr: Config.imApiUrl,
      wsAddr: Config.imWsUrl,
      dataDir: Config.cachePath,
      logLevel: Config.logLevel,
      isLogStandardOutput: Config.logStandardOutput,
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
        onUserTokenExpired: userTokenExpired,
        onUserTokenInvalid: userTokenInvalid,
      ),
    );

    OpenIM.iMManager
      ..setUploadLogsListener(
          OnUploadLogsListener(onUploadProgress: uploadLogsProgress))
      ..userManager.setUserListener(OnUserListener(
          onSelfInfoUpdated: selfInfoUpdated,
          onUserStatusChanged: userStausChanged))
      ..messageManager.setAdvancedMsgListener(OnAdvancedMsgListener(
        onMsgDeleted: messageDeleted,
        onRecvC2CReadReceipt: recvC2CMessageReadReceipt,
        onRecvNewMessage: recvNewMessage,
        onNewRecvMessageRevoked: recvMessageRevoked,
        onRecvOfflineNewMessage: recvOfflineMessage,
        onRecvOnlineOnlyMessage: (msg) {
          AssistantStreamLog.received(msg,
              source: 'online',
              hasReceiver:
                  chatMessageEvents.hasListener || onRecvNewMessage != null);
          if (msg.contentType == MessageType.custom &&
              msg.customElem?.description == 'assistantStream') {
            // Stream deltas are transient SDK data, never business notices.
            publishChatMessage(msg, ChatMessageSource.onlineOnly);
            onRecvNewMessage?.call(msg);
            return;
          }
          if (msg.contentType == MessageType.typing) {
            // Online-only input hints belong to the open SDK conversation;
            // never turn them into persisted messages or business notices.
            publishChatMessage(msg, ChatMessageSource.onlineOnly);
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
      ..setUploadFileListener(OnUploadFileListener(
        onUploadProgress: (id, fileSize, streamSize, storageSize) {
          if (id.startsWith('chat-media:') && fileSize > 0) {
            progressCallback(id.substring('chat-media:'.length),
                (streamSize * 100 ~/ fileSize).clamp(0, 100));
          }
        },
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
    if (notifyStartup) initializedSubject.sink.add(initialized);
    return initialized;
  }

  Future login(String userID, String token) async {
    apiConnectionHealth?.close();
    apiConnectionHealth = null;
    _connectionRecovery?.close();
    _connectionRecovery = null;
    _nativeConnectionWake?.close();
    _nativeConnectionWake = null;
    // The SDK reuses an already logged-in session without another connection
    // callback. Do not replace that session's last real connection/sync state.
    // Logged-in alone is not proof of a live socket: preserve failures too.
    final activeGeneration = _profileSessionGeneration;
    final reusingSession = activeGeneration != null &&
        _sessionQueue.isCurrent(activeGeneration) &&
        _pendingLogout == null &&
        _hasUserInfo &&
        userInfo.value.userID == userID &&
        OpenIM.iMManager.isLogined &&
        OpenIM.iMManager.userID == userID &&
        OpenIM.iMManager.token == token &&
        DataSp.userID == userID &&
        DataSp.imToken == token;
    if (!reusingSession) {
      resetNotificationReadiness();
      imSdkStatus(IMSdkStatus.connecting);
    }
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
            // Native unread callbacks may arrive before Dart login completes.
            initLogic.beginBadgeSession(userID, token);
            CallStateRuntime.instance.activate();
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
            // Hot restart clears Dart login/connection state while the native
            // SDK can remain logged in. Replace that orphaned session so login
            // produces real connection/sync callbacks for the new Dart owner.
            // _logoutSafely skips logout when the native SDK is already out.
            if (!OpenIM.iMManager.isLogined ||
                OpenIM.iMManager.userID != userID ||
                OpenIM.iMManager.token != token) {
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
      bool isCurrentConnection() =>
          !isClosed &&
          _sessionQueue.isCurrent(generation!) &&
          _profileSessionGeneration == generation &&
          DataSp.userID == userID &&
          DataSp.imToken == token;
      apiConnectionHealth = ApiConnectionHealth(isCurrent: isCurrentConnection)..start();
      final nativeWake = _nativeConnectionWake = IMNativeConnectionWake(
          channel: OpenIM.iMManager.channel,
          isCurrentSession: isCurrentConnection,
          isDisconnected: () =>
              currentConnectionStatus == IMSdkStatus.connectionFailed);
      _connectionRecovery = IMConnectionRecovery(
        isCurrent: isCurrentConnection,
        syncRecoverySignals: imSdkStatusPublishSubject
            .distinct((before, after) => before.status == after.status)
            .where((event) =>
                event.status == IMSdkStatus.connectionSucceeded ||
                event.status == IMSdkStatus.connecting ||
                event.status == IMSdkStatus.connectionFailed ||
                event.status == IMSdkStatus.syncFailed)
            .map<void>((_) {}),
        isDisconnected: () =>
            currentConnectionStatus == IMSdkStatus.connecting ||
            currentConnectionStatus == IMSdkStatus.connectionFailed,
        isSyncFailed: () => currentSdkStatus == IMSdkStatus.syncFailed,
        wake: nativeWake.wake,
        onWakeSucceeded: () => historyRecoverySignals.addSafely(null),
        onError: (error) =>
            Logger.print('IM reconnect wake unavailable: ${error.runtimeType}'),
      )..start();
      CallStateRuntime.instance.activate();
      CallStateRuntime.instance.recover();
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
    resetNotificationReadiness();
    apiConnectionHealth?.close();
    apiConnectionHealth = null;
    _connectionRecovery?.close();
    _connectionRecovery = null;
    _nativeConnectionWake?.close();
    _nativeConnectionWake = null;
    CallStateRuntime.instance.reset();
    imSdkStatus(IMSdkStatus.connecting);
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
    initLogic.clearBadgeSession();
    CallStateRuntime.instance.reset();
    DeviceSyncRuntime.instance.resetSession();
    if (Platform.isIOS) {
      await initLogic.endRemotePushSession(logout: false, waitForRemote: false);
    }
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

  @override
  void selfInfoUpdated(UserInfo user) {
    final generation = _profileSessionGeneration;
    if (isClosed ||
        !_hasUserInfo ||
        generation == null ||
        !_sessionQueue.isCurrent(generation) ||
        user.userID?.isNotEmpty != true ||
        user.userID != OpenIM.iMManager.userID ||
        user.userID != DataSp.userID ||
        user.userID != userInfo.value.userID) {
      return;
    }
    super.selfInfoUpdated(user);
    userInfo.update((value) {
      value?.nickname = user.nickname;
      value?.faceURL = user.faceURL;
      value?.remark = user.remark;
      value?.ex = user.ex;
      value?.globalRecvMsgOpt = user.globalRecvMsgOpt;
    });
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
        // Login and the current account's notification preferences are verified.
        // Failed history recovery must not indefinitely mute live messages.
        markNotificationSessionReady(account, token);
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
