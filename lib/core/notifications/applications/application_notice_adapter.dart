import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../routes/app_navigator.dart';
import '../../../routes/app_pages.dart';
import '../message_notification_preferences.dart';
import '../message_notification_sound.dart';
import '../message_notification_runtime.dart' show MessageNotificationSession;
import 'application_notice.dart';
import 'application_notice_runtime.dart';

ApplicationNoticeRuntime createApplicationNotices({
  required FlutterLocalNotificationsPlugin plugin,
  required MessageNotificationSession? Function() session,
  required bool Function() ready,
  required bool Function() foreground,
  required int? Function() globalReceiveOption,
  required bool Function() suppressSound,
}) {
  MessageNotificationPreferences preferences() =>
      MessageNotificationPreferences.read(session()?.accountID ?? '');
  return ApplicationNoticeRuntime(
    session: session,
    ready: ready,
    foreground: foreground,
    allowed: () =>
        globalReceiveOption() != 2 &&
        preferences().notifyWhenOpen &&
        preferences().openedPreview != MessageNotificationPreview.hidden,
    isViewing: (kind) => (kind == ApplicationNoticeKind.friend
            ? [AppRoutes.friendRequests, AppRoutes.processFriendRequests]
            : [AppRoutes.groupRequests, AppRoutes.processGroupRequests])
        .contains(Get.currentRoute),
    verify: (event, account) => _verify(event, account, session),
    readSeen: (account) =>
        SpUtil().getStringList('application_notice_seen_v1_$account') ?? [],
    writeSeen: (account, seen) async {
      await SpUtil().putStringList('application_notice_seen_v1_$account', seen);
    },
    open: (kind) {
      // Existing pages query current state; no approval action is performed.
      if (kind == ApplicationNoticeKind.friend) {
        unawaited(AppNavigator.startFriendRequests());
      } else {
        unawaited(AppNavigator.startGroupRequests());
      }
    },
    show: (event, payload, current) async {
      final prefs = preferences();
      final english = Get.locale?.languageCode == 'en';
      final name = event.nickname.trim().isEmpty
          ? (english ? 'Someone' : '有人')
          : event.nickname.trim();
      final group = event.groupName.trim().isEmpty
          ? (english ? 'Group chat' : '群聊')
          : event.groupName.trim();
      final title = event.kind == ApplicationNoticeKind.friend
          ? (english ? 'New friend request' : '新的好友申请')
          : (english ? 'New group request' : '新的加群申请');
      final detail = event.kind == ApplicationNoticeKind.friend
          ? (english ? '$name wants to add you as a friend' : '$name申请添加你为好友')
          : (english
              ? '$name requested to join "$group". Please review.'
              : '$name申请加入「$group」，请审核');
      final body = prefs.openedPreview == MessageNotificationPreview.detail
          ? detail
          : prefs.openedPreview == MessageNotificationPreview.sender
              ? name
              : title;
      final sound = prefs.messageSoundEnabled && !suppressSound();
      final vibration = prefs.vibration && !suppressSound();
      final digest = sha256.convert(utf8.encode(payload)).bytes;
      final id =
          0x60000000 | ((digest[0] << 16) | (digest[1] << 8) | digest[2]);
      if (!current()) return;
      await plugin.show(
          id,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
                'application_requests_${sound ? prefs.messageSound : 'silent'}_${vibration ? 1 : 0}',
                'Application requests',
                importance: Importance.high,
                priority: Priority.high,
                playSound: sound,
                enableVibration: vibration,
                sound: sound
                    ? RawResourceAndroidNotificationSound(
                        MessageNotificationSoundIds.androidResource(
                            prefs.messageSound))
                    : null,
                visibility: NotificationVisibility.private,
                onlyAlertOnce: true),
            iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBanner: true,
                presentList: true,
                presentBadge: false,
                presentSound: sound,
                sound: sound
                    ? MessageNotificationSoundIds.darwinFilename(
                        prefs.messageSound)
                    : null),
          ),
          payload: payload);
      if (!current()) await plugin.cancel(id);
    },
  );
}

Future<ApplicationNotice?> _verify(ApplicationNotice event, String account,
    MessageNotificationSession? Function() session) async {
  final owner = session();
  bool current() =>
      owner != null &&
      owner.accountID == account &&
      session() == owner &&
      OpenIM.iMManager.userID == account &&
      OpenIM.iMManager.isLogined;
  if (!current()) return null;
  if (event.kind == ApplicationNoticeKind.friend) {
    final rows = await OpenIM.iMManager.friendshipManager
        .getFriendApplicationListAsRecipient();
    if (!current()) return null;
    for (final row in rows) {
      final value = ApplicationNotice.friend(row);
      if (value.eventKey == event.eventKey &&
          value.recipient == account &&
          value.pending) {
        return value;
      }
    }
    return null;
  }
  final members = await OpenIM.iMManager.groupManager
      .getGroupMembersInfo(groupID: event.groupID, userIDList: [account]);
  if (!current() ||
      !members.any((m) =>
          m.userID == account &&
          (m.roleLevel == GroupRoleLevel.owner ||
              m.roleLevel == GroupRoleLevel.admin))) {
    return null;
  }
  for (var offset = 0; current(); offset += 50) {
    final rows = await OpenIM.iMManager.groupManager
        .getGroupApplicationListAsRecipient(
            req: GetGroupApplicationListAsRecipientReq(
                groupIDs: [event.groupID],
                handleResults: [0],
                offset: offset,
                count: 50));
    if (!current()) return null;
    for (final row in rows) {
      final value = ApplicationNotice.group(row);
      if (value.eventKey == event.eventKey && value.pending) return value;
    }
    if (rows.length < 50) break;
  }
  return null;
}
