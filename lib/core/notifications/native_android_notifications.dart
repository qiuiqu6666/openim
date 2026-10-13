import 'dart:io';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:openim_common/openim_common.dart';
import 'message_notification_preferences.dart';

/// Native receives messages directly. This bridge carries settings/UI state only.
class NativeAndroidNotifications {
  NativeAndroidNotifications({bool? isAndroid, bool? enabled})
      : _isAndroid = isAndroid ?? Platform.isAndroid,
        _enabled =
            enabled ?? const bool.fromEnvironment('NATIVE_IM_NOTIFICATIONS');
  final bool _isAndroid;
  final bool _enabled;
  static const _channel = MethodChannel('openim_native_im');
  // Opt in for acceptance builds; keep the existing release path until real-device gates pass.
  bool ownsNotifications = false;
  Future<void> initialize(
      void Function(NotificationResponse) onResponse) async {
    if (!_isAndroid || !_enabled) return;
    ownsNotifications = await _channel.invokeMethod<bool>('initialize') == true;
    if (!ownsNotifications) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'notificationAction') return;
      final value = Map<String, dynamic>.from(call.arguments as Map);
      onResponse(NotificationResponse(
        notificationResponseType: value['actionId'] == 'reply'
            ? NotificationResponseType.selectedNotificationAction
            : NotificationResponseType.selectedNotification,
        id: value['id'] as int?,
        payload: value['payload'] as String?,
        actionId: value['actionId'] as String?,
        input: value['input'] as String?,
      ));
    });
    await _channel.invokeMethod<void>('readyForActions');
  }

  Future<void> configure(
      {required String accountID,
      required String sessionKey,
      String? activeConversationID,
      required bool suppressSound}) async {
    if (!ownsNotifications) return;
    final p = MessageNotificationPreferences.read(accountID);
    await _channel.invokeMethod<void>('configure', {
      'accountID': accountID,
      'sessionKey': sessionKey,
      'activeConversationID': activeConversationID ?? '',
      'suppressSound': suppressSound,
      'preferences': {
        'notifyWhenOpen': p.notifyWhenOpen,
        'notifyWhenClosed': p.notifyWhenClosed,
        'openedPreview': p.openedPreview.name,
        'closedPreview': p.closedPreview.name,
        'quickReply': p.quickReply,
        'messageSoundEnabled': p.messageSoundEnabled,
        'messageSound': p.messageSound,
        'vibration': p.vibration,
        'labels': {
          'offlineMessage': StrRes.offlineMessage,
          'groupChat': StrRes.groupChat,
          'reply': StrRes.reply,
          'picture': StrRes.picture,
          'voice': StrRes.voice,
          'video': StrRes.video,
          'file': StrRes.file,
          'everyone': StrRes.everyone,
          'chatRecord': StrRes.chatRecord,
          'carte': StrRes.carte,
          'toolboxLocation': StrRes.toolboxLocation,
          'emoji': StrRes.emoji,
          'unsupportedMessage': StrRes.unsupportedMessage,
          'fundExclusivePacket': StrRes.fundExclusivePacket,
          'fundLuckyPacket': StrRes.fundLuckyPacket,
          'fundPacket': StrRes.fundPacket,
          'fundGroupTransfer': StrRes.fundGroupTransfer,
          'fundTransfer': StrRes.fundTransfer,
          'diceLabel': StrRes.diceLabel,
          'dicePoint': StrRes.dicePoint(1).replaceFirst('1', '%s'),
          'callVoice': StrRes.callVoice,
          'callVideo': StrRes.callVideo,
          'audioAndVideoCall': StrRes.audioAndVideoCall,
          'cancelled': StrRes.cancelled,
          'cancelledByCaller': StrRes.cancelledByCaller,
          'rejected': StrRes.rejected,
          'rejectedByCaller': StrRes.rejectedByCaller,
          'callTimeout': StrRes.callTimeout,
          'callDuration': StrRes.callDuration,
          'networkAnomaly': StrRes.networkAnomaly,
          'otherAccepted': Get.locale?.languageCode == 'en'
              ? 'Answered on another device'
              : '已在其他设备接听',
          'blockedByFriendHint': StrRes.blockedByFriendHint,
          'deletedByFriendHint': StrRes.deletedByFriendHint,
          'removedFromGroupHint': StrRes.removedFromGroupHint,
          'groupDisbanded': StrRes.groupDisbanded,
        },
      },
    });
  }

  Future<void> clear(String? sessionKey) async {
    if (ownsNotifications) {
      await _channel.invokeMethod<void>('clear', {'sessionKey': sessionKey});
    }
  }

  Future<void> cancel(int id) async {
    if (ownsNotifications) {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    }
  }
}
