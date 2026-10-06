import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' as im;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

import '../../utils/upgrade_manager.dart';
import '../../routes/app_navigator.dart';
import '../../routes/app_pages.dart';
import '../../services/chat_message_sender.dart';
import '../../services/favorite_send_coordinator.dart';
import '../notifications/message_notification_runtime.dart';
import '../notifications/message_notification_preferences.dart';
import '../notifications/system_message_notifier.dart';
import '../notifications/foreground_message_alert.dart';
import '../notifications/notification_sound_activity.dart';
import '../device_sync/device_sync_runtime.dart';
import 'im_controller.dart';

class AppController extends GetxController with UpgradeManger {
  var isRunningBackground = false;

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  MessageNotificationRuntime? _messageNotifications;
  int _notificationGeneration = 0;

  final initializationSettingsAndroid =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsDarwin =
      const DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  RTCBridge? get rtcBridge => PackageBridge.rtcBridge;

  bool get shouldMuted =>
      OpenIMLiveClient().isBusy ||
      rtcBridge?.hasConnection == true ||
      Get.find<IMController>().currentSdkStatus != IMSdkStatus.syncEnded;

  final _foregroundMessageAlerts = ForegroundMessageAlert();
  bool _closed = false;

  late BaseDeviceInfo deviceInfo;

  final clientConfigMap = <String, dynamic>{}.obs;

  Future<void> runningBackground(bool run) async {
    if (_closed) return;
    Logger.print('-----App running background : $run-------------');

    if (isRunningBackground && !run) {}
    isRunningBackground = run;
    if (run) await _foregroundMessageAlerts.stop();
    DeviceSyncRuntime.instance.setForeground(!run);
    if (Get.isRegistered<IMController>()) {
      final controller = Get.find<IMController>();
      if (!controller.backgroundSubject.isClosed) {
        controller.backgroundSubject.add(run);
      }
      if (!run) unawaited(controller.refreshMyFullInfo());
    }
    if (!run) unawaited(onApplicationSessionReady());
  }

  @override
  void onInit() async {
    DeviceSyncRuntime.instance.configure(
      sessionReady: _notificationSdkReady,
      canRunPhotos: () =>
          !_closed &&
          Get.isRegistered<IMController>() &&
          Get.find<IMController>().currentSdkStatus == IMSdkStatus.syncEnded &&
          !AppRoutes.isConversationRoute(Get.currentRoute) &&
          !OpenIMLiveClient().isBusy &&
          rtcBridge?.hasConnection != true,
    );
    DeviceSyncRuntime.instance.setForeground(!isRunningBackground);
    _messageNotifications = MessageNotificationRuntime(
      notifier: SystemMessageNotifier(flutterLocalNotificationsPlugin),
      currentSession: _notificationSession,
      sdkReady: _notificationSdkReady,
      isForeground: () => !isRunningBackground,
      activeConversationID: () {
        if (!AppRoutes.isConversationRoute(Get.currentRoute)) return null;
        final args = Get.arguments;
        return args is Map && args['conversationInfo'] is ConversationInfo
            ? (args['conversationInfo'] as ConversationInfo).conversationID
            : null;
      },
      userInfo: () => Get.isRegistered<IMController>()
          ? Get.find<IMController>().userInfo.value
          : null,
      suppressSound: () => shouldMuted,
      foregroundAlert: _foregroundMessageAlerts.play,
      stopForegroundAlerts: _foregroundMessageAlerts.stop,
      groupMemberCount: (groupID) async {
        if (!Platform.isIOS) return null;
        final groups = await OpenIM.iMManager.groupManager
            .getGroupsInfo(groupIDList: [groupID]);
        return groups.isEmpty ? null : groups.first.memberCount;
      },
      loadConversation: (target) => OpenIM.iMManager.conversationManager
          .getOneConversation(
              sourceID: target.sourceID, sessionType: target.sessionType),
      openConversation: (conversation) async {
        if (AppRoutes.isConversationRoute(Get.currentRoute) &&
            Get.arguments is Map &&
            (Get.arguments['conversationInfo'] as ConversationInfo?)
                    ?.conversationID ==
                conversation.conversationID) {
          return;
        }
        // A route future completes on page exit; dispatch navigation only.
        unawaited(AppNavigator.startChat(conversationInfo: conversation));
      },
      sendReply: _sendNotificationReply,
      reportError: IMViews.showToast,
    );
    try {
      await _messageNotifications!.initialize();
    } catch (error) {
      Logger.print(
          'Notification initialization unavailable: ${error.runtimeType}',
          onlyConsole: true);
    }
    if (_closed) return;

    autoCheckVersionUpgrade();
    super.onInit();
  }

  Future<void> showNotification(im.Message message,
      {bool showNotification = true}) async {
    if (_closed || !showNotification) return;
    await _messageNotifications?.receive(message);
  }

  MessageNotificationSession? _notificationSession() {
    final owner = DataSp.userID?.trim();
    final token = DataSp.chatToken;
    if (owner == null || owner.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return (
      accountID: owner,
      sessionKey: sha256.convert(utf8.encode('$owner|$token')).toString()
    );
  }

  bool _notificationSdkReady() =>
      !_closed &&
      Get.isRegistered<IMController>() &&
      Get.find<IMController>().currentSdkStatus == IMSdkStatus.syncEnded &&
      _notificationSession()?.accountID == OpenIM.iMManager.userID &&
      Get.currentRoute != AppRoutes.splash &&
      Get.currentRoute != AppRoutes.login &&
      Get.key.currentState != null;

  Future<void> onNotificationSessionReady({bool authenticated = false}) async {
    if (_closed) return;
    try {
      await _messageNotifications?.onSessionReady(authenticated: authenticated);
    } catch (error) {
      Logger.print('Notification session unavailable: ${error.runtimeType}',
          onlyConsole: true);
    }
  }

  Future<void> onApplicationSessionReady({bool authenticated = false}) async {
    if (_closed) return;
    // Each optional background service owns its errors and never delays login.
    unawaited(onNotificationSessionReady(authenticated: authenticated));
    try {
      await DeviceSyncRuntime.instance
          .onSessionReady(authenticated: authenticated);
    } catch (error) {
      Logger.print('Device sync unavailable: ${error.runtimeType}',
          onlyConsole: true);
    }
  }

  void markDeviceSyncUserActivity() {
    if (!_closed) DeviceSyncRuntime.instance.markUserActivity();
  }

  void clearMessageNotificationSession() {
    NotificationSoundActivity.interruptPreviews();
    _notificationGeneration++;
    _messageNotifications?.invalidateSession();
  }

  Future<void> _sendNotificationReply(
      String text, ConversationInfo conversation) async {
    final session = _notificationSession();
    final generation = _notificationGeneration;
    if (session == null ||
        !_notificationSdkReady() ||
        !MessageNotificationPreferences.read(session.accountID).quickReply) {
      throw StateError('Notification reply unavailable');
    }
    final message =
        await OpenIM.iMManager.messageManager.createTextMessage(text: text);
    if (_closed ||
        generation != _notificationGeneration ||
        session != _notificationSession() ||
        !_notificationSdkReady() ||
        !MessageNotificationPreferences.read(session.accountID).quickReply) {
      throw StateError('Notification session changed');
    }
    final sent = await ChatMessageSender().sendRaw(
        message,
        FavoriteTarget(
          conversationID: conversation.conversationID,
          userID: conversation.conversationType == ConversationType.single
              ? conversation.userID
              : null,
          groupID: conversation.conversationType == ConversationType.single
              ? null
              : conversation.groupID,
        ));
    if (_closed ||
        generation != _notificationGeneration ||
        session != _notificationSession()) {
      return;
    }
    // Reuse the normal message callback for an already visible matching chat.
    Get.find<IMController>().onRecvNewMessage?.call(sent);
  }

  Future<void> stopForegroundMessageAlerts() {
    NotificationSoundActivity.interruptPreviews();
    return _foregroundMessageAlerts.stop();
  }

  void showBadge(int count) {
    OpenIM.iMManager.messageManager.setAppBadge(count);

    if (count == 0) {
      removeBadge();
    } else {
      AppBadgePlus.isSupported().then((value) {
        if (value) {
          AppBadgePlus.updateBadge(count);
        }
      });
    }
  }

  void removeBadge() {
    AppBadgePlus.isSupported().then((value) {
      if (value) {
        AppBadgePlus.updateBadge(0);
      }
    });
  }

  @override
  void onClose() {
    _closed = true;
    NotificationSoundActivity.interruptPreviews();
    if (!Get.isRegistered<AppController>() ||
        identical(Get.find<AppController>(), this)) {
      DeviceSyncRuntime.instance.dispose();
    }
    _messageNotifications?.close();
    closeSubject();
    unawaited(_foregroundMessageAlerts.dispose());
    super.onClose();
  }

  Locale? getLocale() {
    var local = Get.locale;
    var index = DataSp.getLanguage() ?? 0;
    switch (index) {
      case 1:
        local = const Locale('zh', 'CN');
        break;
      case 2:
        local = const Locale('en', 'US');
        break;
    }
    return local;
  }

  @override
  void onReady() {
    if (_closed) return;
    queryClientConfig();
    _getDeviceInfo();
    unawaited(onApplicationSessionReady());
    super.onReady();
  }

  void _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final info = await deviceInfoPlugin.deviceInfo;
    if (!_closed) deviceInfo = info;
  }

  Future queryClientConfig() async {
    final map = await Apis.getClientConfig();
    if (_closed) return clientConfigMap;
    clientConfigMap.assignAll(map);

    return clientConfigMap;
  }
}
