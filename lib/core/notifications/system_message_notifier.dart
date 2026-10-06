import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:openim_common/openim_common.dart';

import 'message_notification_actions.dart';
import 'message_notification_policy.dart';
import 'message_notification_sound.dart';
import 'message_notification_target.dart';

/// Uses native heads-up/communication notifications, never a Flutter overlay.
class SystemMessageNotifier {
  SystemMessageNotifier(this.plugin, {TargetPlatform? platform})
      : _platform = platform ?? defaultTargetPlatform;
  final FlutterLocalNotificationsPlugin plugin;
  final TargetPlatform _platform;
  static const _bridge = MethodChannel('openim_chat_notifications');
  static const replyCategory = 'chat_message_reply';
  Future<Uint8List>? _appIcon;

  Future<void> initialize(
      void Function(NotificationResponse) onResponse) async {
    await plugin.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(replyCategory, actions: [
              DarwinNotificationAction.text(
                MessageNotificationActions.replyAction,
                StrRes.reply,
                buttonTitle: StrRes.send,
                placeholder: StrRes.reply,
                options: {DarwinNotificationActionOption.foreground},
              ),
            ]),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: onResponse,
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      onResponse(launch!.notificationResponse!);
    }
  }

  Future<void> requestPermission() async {
    if (_platform == TargetPlatform.android) {
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (_platform == TargetPlatform.iOS) {
      await plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> setSession(String sessionKey) async {
    if (_platform != TargetPlatform.iOS) return;
    try {
      await _bridge.invokeMethod('setSession', {'sessionKey': sessionKey});
    } on MissingPluginException {
      // Older platforms retain ordinary native notifications.
    }
  }

  Future<void> clearSession(String? sessionKey) async {
    if (_platform != TargetPlatform.iOS) return;
    try {
      await _bridge.invokeMethod('clearSession', {'sessionKey': sessionKey});
    } on MissingPluginException {
      // A bridge is optional for native app-icon notifications.
    }
  }

  Future<void> invalidate(int id, String sessionKey) async {
    if (_platform != TargetPlatform.iOS) return;
    try {
      await _bridge.invokeMethod(
          'invalidateNotification', {'sessionKey': sessionKey, 'id': id});
    } on MissingPluginException {
      // Ordinary native notifications have no in-flight avatar donation.
    }
  }

  Future<void> show({
    required int id,
    required MessageNotificationTarget target,
    required MessageNotificationPresentation presentation,
    required bool sound,
    required bool vibration,
    String? avatarPath,
    bool alert = true,
    DateTime? timestamp,
    bool Function()? isCurrent,
    String? senderID,
    int? groupMemberCount,
  }) async {
    if (isCurrent?.call() == false) return;
    final payload = target.encode();
    if (_platform == TargetPlatform.iOS && avatarPath != null) {
      try {
        final handled = await _bridge.invokeMethod<bool>(
          'showCommunicationNotification',
          {
            'id': id,
            'sessionKey': target.sessionKey,
            'conversationID': target.conversationID,
            'title': presentation.title,
            'body': presentation.body,
            'payload': payload,
            'categoryIdentifier': presentation.showReply ? replyCategory : '',
            'senderID': senderID ?? target.sourceID,
            'senderName': presentation.senderName.isEmpty
                ? presentation.title
                : presentation.senderName,
            'recipientID': target.accountID,
            'recipientName': target.accountID,
            'isGroup': presentation.isGroup,
            'groupMemberCount': groupMemberCount,
            'senderAvatarPath': avatarPath,
            'conversationAvatarPath': avatarPath,
            'playSound': sound && alert,
            'soundName': MessageNotificationSoundIds.darwinFilename(
                presentation.soundID),
            'presentSound': sound && alert,
            'presentBanner': alert,
            'presentList': true,
            'alert': alert,
          },
        );
        if (handled == true) return;
      } on PlatformException {
        // Native communication capabilities can be unavailable on old iOS.
      } on MissingPluginException {
        // Fall back to the OS app icon without a custom in-app banner.
      }
    }
    final AndroidBitmap<Object> avatar = avatarPath == null
        ? ByteArrayAndroidBitmap(await (_appIcon ??= rootBundle
            .load('assets/img/99chat_logo.png')
            .then((data) => data.buffer.asUint8List())))
        : FilePathAndroidBitmap(avatarPath);
    final personIcon = avatarPath == null
        ? const FlutterBitmapAssetAndroidIcon('assets/img/99chat_logo.png')
        : BitmapFilePathAndroidIcon(avatarPath);
    final style = MessagingStyleInformation(
      Person(key: target.accountID, name: 'Me'),
      conversationTitle: presentation.title,
      groupConversation: presentation.isGroup,
      messages: [
        Message(
            presentation.isGroup &&
                    presentation.senderName.isNotEmpty &&
                    presentation.body.startsWith('${presentation.senderName}: ')
                ? presentation.body
                    .substring(presentation.senderName.length + 2)
                : presentation.body,
            timestamp ?? DateTime.now(),
            Person(
                name: presentation.isGroup
                    ? presentation.senderName
                    : presentation.title,
                key: senderID ?? target.sourceID,
                icon: personIcon)),
      ],
    );
    if (isCurrent?.call() == false) return;
    await plugin.show(
      id,
      presentation.title,
      presentation.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          sound
              ? 'chat_messages_v2_${MessageNotificationSoundIds.normalizedId(presentation.soundID)}_v${vibration ? 1 : 0}'
              : 'chat_messages_v2_silent_v${vibration ? 1 : 0}',
          'Chat messages',
          channelDescription: 'New chat messages and quick replies',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          styleInformation: style,
          largeIcon: avatar,
          playSound: sound,
          sound: sound
              ? RawResourceAndroidNotificationSound(
                  MessageNotificationSoundIds.androidResource(
                      presentation.soundID))
              : null,
          enableVibration: vibration,
          onlyAlertOnce: !alert,
          silent: !alert,
          visibility: NotificationVisibility.private,
          actions: presentation.showReply
              ? [
                  AndroidNotificationAction(
                    MessageNotificationActions.replyAction,
                    StrRes.reply,
                    showsUserInterface: true,
                    allowGeneratedReplies: true,
                    cancelNotification: false,
                    inputs: [
                      AndroidNotificationActionInput(label: StrRes.reply)
                    ],
                  ),
                ]
              : null,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: alert,
          presentBanner: alert,
          presentList: true,
          presentSound: sound && alert,
          sound: sound && alert
              ? MessageNotificationSoundIds.darwinFilename(presentation.soundID)
              : null,
          threadIdentifier: target.conversationID,
          categoryIdentifier: presentation.showReply ? replyCategory : null,
          interruptionLevel:
              alert ? InterruptionLevel.active : InterruptionLevel.passive,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> cancel(int id) => plugin.cancel(id);
  Future<void> cancelAll() => plugin.cancelAll();
}
