import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screen_lock/flutter_screen_lock.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/controller/app_controller.dart';
import '../../core/user_activity/activity_runtime.dart';
import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../../core/session/local_session_exit.dart';
import '../../routes/app_navigator.dart';
import '../../services/chat_history_cache.dart';
import '../../widgets/screen_lock_title.dart';
import '../chat/fund/fund_card_state_cache.dart';
import '../group_features/data/group_feature_runtime.dart';
import '../mine/secondary/calls/data/call_records_runtime.dart';

class HomeLogic extends SuperController {
  final pushLogic = Get.find<PushController>();
  final imLogic = Get.find<IMController>();
  final cacheLogic = Get.find<CacheController>();
  final initLogic = Get.find<AppController>();
  final index = 0.obs;
  final unreadMsgCount = 0.obs;
  final unhandledFriendApplicationCount = 0.obs;
  final unhandledGroupApplicationCount = 0.obs;
  final unhandledCount = 0.obs;
  String? _lockScreenPwd;
  bool _isShowScreenLock = false;
  bool? _isAutoLogin;
  final auth = LocalAuthentication();
  final _errorController = PublishSubject<String>();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _closed = false;
  bool _endingSession = false;
  final _sessionAccount = OpenIM.iMManager.userID;
  final _sessionToken = DataSp.chatToken;

  Future<void> endSession(
      {bool invalid = false, bool resetScreenLock = false}) async {
    if (_closed ||
        _endingSession ||
        _sessionAccount != OpenIM.iMManager.userID ||
        _sessionToken != DataSp.chatToken) return;
    _endingSession = true;
    try {
      await exitLocalSession(
        logoutSdk: imLogic.logout,
        clearLocal: () async {
          GroupFeatureRuntime.reset();
          CallRecordsRuntime.resetSession();
          await DataSp.removeLoginCertificate();
          if (resetScreenLock) {
            await DataSp.clearLockScreenPassword();
            await DataSp.closeBiometric();
          }
          conversationsAtFirstPage.clear();
          PushController.logout();
        },
        navigate: () {
          if (_closed) return;
          LoadingView.singleton.dismiss();
          if (invalid) IMViews.showToast(ApiErrorMessages.sessionExpired);
          AppNavigator.startLogin();
        },
        onCleanupError: (error, _) =>
            Logger.print('SDK logout cleanup failed: $error'),
      );
    } catch (error) {
      Logger.print('Local logout cleanup failed: $error');
    }
  }

  Future<void> _endInvalidSession() => endSession(invalid: true);

  var conversationsAtFirstPage = <ConversationInfo>[];

  switchTab(index) {
    this.index.value = index;
    ActivityRuntime.instance.setHomeTab(index);
  }

  _getUnreadMsgCount() {
    OpenIM.iMManager.conversationManager.getTotalUnreadMsgCount().then((count) {
      if (_closed) return;
      unreadMsgCount.value = int.tryParse(count) ?? 0;
      initLogic.showBadge(unreadMsgCount.value);
    });
  }

  void getUnhandledFriendApplicationCount() async {
    var i = 0;
    var list = await OpenIM.iMManager.friendshipManager
        .getFriendApplicationListAsRecipient();
    if (_closed) return;
    final haveReadList =
        DataSp.getHaveReadUnHandleFriendApplication()?.toSet() ?? <String>{};
    for (var info in list) {
      var id = IMUtils.buildFriendApplicationID(info);
      if (!haveReadList.contains(id)) {
        if (info.handleResult == 0) i++;
      }
    }
    unhandledFriendApplicationCount.value = i;
    unhandledCount.value = unhandledGroupApplicationCount.value + i;
  }

  void getUnhandledGroupApplicationCount() async {
    var i = 0;
    var list = await OpenIM.iMManager.groupManager
        .getGroupApplicationListAsRecipient();
    if (_closed) return;
    final haveReadList =
        DataSp.getHaveReadUnHandleGroupApplication()?.toSet() ?? <String>{};
    for (var info in list) {
      var id = IMUtils.buildGroupApplicationID(info);
      if (!haveReadList.contains(id)) {
        if (info.handleResult == 0) i++;
      }
    }
    unhandledGroupApplicationCount.value = i;
    unhandledCount.value = unhandledFriendApplicationCount.value + i;
  }

  @override
  void onInit() {
    _isAutoLogin = Get.arguments != null ? Get.arguments['isAutoLogin'] : false;
    if (_isAutoLogin == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLockScreenPwd());
    }
    if (Get.arguments != null) {
      conversationsAtFirstPage = Get.arguments['conversations'] ?? [];
    }
    _subscriptions.add(imLogic.unreadMsgCountEventSubject.listen((value) {
      if (_closed) return;
      unreadMsgCount.value = value;
    }));
    _subscriptions.add(imLogic.friendApplicationChangedSubject.listen((value) {
      if (_closed) return;
      getUnhandledFriendApplicationCount();
    }));
    _subscriptions.add(imLogic.groupApplicationChangedSubject.listen((value) {
      if (_closed) return;
      getUnhandledGroupApplicationCount();
    }));

    _subscriptions.add(imLogic.imSdkStatusPublishSubject.listen((value) {
      if (_closed) return;
      if (value.status == IMSdkStatus.syncStart) {
        _getRTCInvitationStart();
      }
    }));

    _subscriptions.add(imLogic.onKickedOfflineSubject.listen((_) {
      unawaited(_endInvalidSession());
    }));
    _subscriptions.add(Apis.kickoffController.stream.listen((_) {
      unawaited(_endInvalidSession());
    }));
    super.onInit();
  }

  @override
  void onReady() {
    if (_closed) return;
    _getRTCInvitationStart();
    _getUnreadMsgCount();
    getUnhandledFriendApplicationCount();
    getUnhandledGroupApplicationCount();
    unawaited(CallRecordsRuntime.repository.refresh());
    super.onReady();
  }

  @override
  void onClose() {
    _closed = true;
    ChatHistoryCache.clear();
    FundCardStateCache.shared.clear();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _errorController.close();
    super.onClose();
  }

  _localAuth() async {
    final didAuthenticate = await IMUtils.checkingBiometric(auth);
    if (didAuthenticate) {
      Get.back();
    }
  }

  _showLockScreenPwd() async {
    if (_closed || _isShowScreenLock) return;
    _lockScreenPwd = DataSp.getLockScreenPassword();
    if (null != _lockScreenPwd) {
      final isEnabledBiometric = DataSp.isEnabledBiometric() == true;
      bool enabled = false;
      if (isEnabledBiometric) {
        final isSupportedBiometrics = await auth.isDeviceSupported();
        final canCheckBiometrics = await auth.canCheckBiometrics;
        enabled = isSupportedBiometrics && canCheckBiometrics;
      }
      if (_closed) return;
      _isShowScreenLock = true;
      screenLock(
        context: Get.context!,
        correctString: _lockScreenPwd!,
        maxRetries: 3,
        title: ScreenLockTitle(stream: _errorController.stream),
        canCancel: false,
        customizedButtonChild: enabled ? const Icon(Icons.fingerprint) : null,
        customizedButtonTap: enabled ? () async => await _localAuth() : null,
        onUnlocked: () {
          _isShowScreenLock = false;
          Get.back();
        },
        onMaxRetries: (_) async {
          Get.back();
          await endSession(resetScreenLock: true);
        },
        onError: (retries) {
          _errorController.sink.add(
            retries.toString(),
          );
        },
      );
    }
  }

  @override
  void onDetached() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {}

  @override
  void onResumed() {}

  void _getRTCInvitationStart() async {}

  @override
  void onHidden() {}
}
