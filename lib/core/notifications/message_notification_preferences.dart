import 'dart:async';

import 'package:openim_common/openim_common.dart' show SpUtil;
import 'message_notification_sound.dart';
import 'legacy_notification_preferences.dart';

enum MessageNotificationPreview {
  detail,
  sender,
  none,
  hidden;

  static MessageNotificationPreview parse(Object? value) => switch (value) {
        'sender' => sender,
        'none' => none,
        'hidden' => hidden,
        _ => detail,
      };
}

/// Account-local notification preferences, read afresh for each incoming event.
/// SDK global and conversation reception options remain inputs to the policy.
class MessageNotificationPreferences {
  static final _changes = StreamController<String>.broadcast(sync: true);
  static Stream<String> get changes => _changes.stream;

  /// Invalidate native work immediately when the account changes its choices.
  static void notifyChanged(String accountID) => _changes.add(accountID);

  const MessageNotificationPreferences({
    this.notifyWhenOpen = true,
    this.notifyWhenClosed = true,
    this.openedPreview = MessageNotificationPreview.detail,
    this.closedPreview = MessageNotificationPreview.detail,
    this.quickReply = true,
    this.messageSoundEnabled = true,
    this.messageSound = MessageNotificationSoundIds.defaultId,
    this.vibration = true,
  });

  final bool notifyWhenOpen;
  final bool notifyWhenClosed;
  final MessageNotificationPreview openedPreview;
  final MessageNotificationPreview closedPreview;
  final bool quickReply;
  final bool messageSoundEnabled;
  final String messageSound;
  final bool vibration;

  static MessageNotificationPreferences read(String accountID) {
    final owner = accountID.trim();
    final prefix = '99chat_settings_${owner.isEmpty ? 'anonymous' : owner}_';
    final storage = SpUtil();
    final inherited = legacyNotificationDefaults(owner);
    Object? value(String key) =>
        storage.getDynamic('$prefix$key') ?? inherited[key];
    bool enabled(String key) => switch (value(key)) {
          bool result => result,
          _ => true,
        };
    return MessageNotificationPreferences(
      notifyWhenOpen: enabled('notify_when_open'),
      notifyWhenClosed: enabled('notify_when_closed'),
      openedPreview:
          MessageNotificationPreview.parse(value('notify_open_preview')),
      closedPreview:
          MessageNotificationPreview.parse(value('notify_closed_preview')),
      quickReply: enabled('notify_quick_reply'),
      messageSoundEnabled: enabled('message_sound_enabled'),
      messageSound: MessageNotificationSoundIds.normalizedId(
          value('message_sound') is String
              ? value('message_sound') as String
              : null),
      vibration: enabled('vibration'),
    );
  }
}
