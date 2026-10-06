import 'dart:ui';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/notifications/message_notification_policy.dart';
import 'package:openim/core/notifications/message_notification_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Message _message() => Message(
      clientMsgID: 'message-1',
      contentType: MessageType.text,
      sessionType: ConversationType.single,
      sendID: 'peer',
      recvID: 'self',
      senderNickname: 'Alice',
      senderFaceUrl: 'https://example.com/sender.png',
      textElem: TextElem(content: 'SDK message body'),
    );

ConversationInfo _conversation() => ConversationInfo(
      conversationID: 'single-peer',
      conversationType: ConversationType.single,
      userID: 'peer',
      showName: 'Alice remark',
      faceURL: 'https://example.com/conversation.png',
      recvMsgOpt: 0,
    );

ConversationInfo _group() => ConversationInfo(
      conversationID: 'group-team',
      conversationType: ConversationType.superGroup,
      groupID: 'team',
      showName: 'Team',
      faceURL: 'https://example.com/group.png',
      recvMsgOpt: 0,
    );

MessageNotificationPresentation? _present({
  Message? message,
  ConversationInfo? conversation,
  bool isForeground = true,
  String? activeConversationID,
  String currentUserID = 'self',
  int? globalRecvMsgOpt,
  MessageNotificationPreferences preferences =
      const MessageNotificationPreferences(),
}) =>
    MessageNotificationPolicy.present(
      message: message ?? _message(),
      conversation: conversation ?? _conversation(),
      currentUserID: currentUserID,
      isForeground: isForeground,
      activeConversationID: activeConversationID,
      globalRecvMsgOpt: globalRecvMsgOpt,
      preferences: preferences,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  tearDown(Get.reset);

  test('missing persisted values preserve current notification defaults', () {
    final preferences = MessageNotificationPreferences.read('self');
    expect(preferences.notifyWhenOpen, isTrue);
    expect(preferences.notifyWhenClosed, isTrue);
    expect(preferences.openedPreview, MessageNotificationPreview.detail);
    expect(preferences.closedPreview, MessageNotificationPreview.detail);
    expect(preferences.quickReply, isTrue);
    expect(preferences.messageSoundEnabled, isTrue);
    expect(preferences.vibration, isTrue);
  });

  test('preferences are account isolated and reread after a setting changes',
      () async {
    const key = '99chat_settings_self_';
    final storage = SpUtil();
    await storage.putBool('${key}notify_when_open', false);
    await storage.putBool('${key}notify_when_closed', false);
    await storage.putString('${key}notify_open_preview', 'sender');
    await storage.putString('${key}notify_closed_preview', 'none');
    await storage.putBool('${key}notify_quick_reply', false);
    await storage.putBool('${key}message_sound_enabled', false);
    await storage.putBool('${key}vibration', false);
    final first = MessageNotificationPreferences.read('self');
    expect(first.notifyWhenOpen, isFalse);
    expect(first.notifyWhenClosed, isFalse);
    expect(first.openedPreview, MessageNotificationPreview.sender);
    expect(first.closedPreview, MessageNotificationPreview.none);
    expect(first.quickReply, isFalse);
    expect(first.messageSoundEnabled, isFalse);
    expect(first.vibration, isFalse);
    expect(MessageNotificationPreferences.read('other').notifyWhenOpen, isTrue);

    await storage.putBool('${key}notify_when_open', true);
    await storage.putString('${key}notify_open_preview', 'detail');
    final second = MessageNotificationPreferences.read('self');
    expect(second.notifyWhenOpen, isTrue);
    expect(second.openedPreview, MessageNotificationPreview.detail);
    expect(first.notifyWhenOpen, isFalse); // Earlier snapshots are immutable.
  });

  test('blank account keys and invalid persisted values are handled safely',
      () async {
    await SpUtil().putBool('99chat_settings_anonymous_notify_when_open', false);
    expect(MessageNotificationPreferences.read('  ').notifyWhenOpen, isFalse);
    await SpUtil().putString('99chat_settings_self_notify_when_open', 'bad');
    await SpUtil().putString('99chat_settings_self_notify_open_preview', 'bad');
    final preferences = MessageNotificationPreferences.read(' self ');
    expect(preferences.notifyWhenOpen, isTrue);
    expect(preferences.openedPreview, MessageNotificationPreview.detail);
    expect(_present(currentUserID: ''), isNull);
  });

  for (final type in [
    MessageType.typing,
    MessageType.friendAddedNotification,
    MessageType.oaNotification,
    MessageType.revokeMessageNotification,
    MessageType.businessNotification,
    MessageType.groupHasReadReceiptNotification,
  ]) {
    test('non-chat event $type does not become a message notification', () {
      expect(_present(message: _message()..contentType = type), isNull);
    });
  }

  test('own messages and missing content type are suppressed', () {
    expect(_present(message: _message()..sendID = 'self'), isNull);
    expect(_present(message: _message()..contentType = null), isNull);
    expect(
        _present(conversation: _conversation()..conversationID = ''), isNull);
  });

  test('global and conversation do-not-disturb suppress both app states', () {
    for (final foreground in [true, false]) {
      expect(_present(isForeground: foreground, globalRecvMsgOpt: 2), isNull);
      for (final option in [1, 2]) {
        expect(
            _present(
                isForeground: foreground,
                conversation: _conversation()..recvMsgOpt = option),
            isNull);
      }
    }
    expect(_present(globalRecvMsgOpt: 0), isNotNull);
  });

  test('SDK push suppression works with parsed and raw attached information',
      () {
    expect(
        _present(
            message: _message()
              ..attachedInfoElem =
                  AttachedInfoElem(notSenderNotificationPush: true)),
        isNull);
    expect(
        _present(
            message: _message()
              ..attachedInfo = '{"notSenderNotificationPush":true}'),
        isNull);
    expect(_present(message: _message()..attachedInfo = 'broken'), isNotNull);
  });

  test('system conversation types do not surface as ordinary chat previews',
      () {
    expect(
        _present(
            conversation: _conversation()
              ..conversationType = ConversationType.notification),
        isNull);
    expect(
        _present(
            message: _message()..sessionType = ConversationType.notification),
        isNull);
  });

  test('front and background switches are independent', () {
    const openedOff = MessageNotificationPreferences(notifyWhenOpen: false);
    expect(_present(preferences: openedOff), isNull);
    expect(_present(preferences: openedOff, isForeground: false), isNotNull);
    const closedOff = MessageNotificationPreferences(notifyWhenClosed: false);
    expect(_present(preferences: closedOff), isNotNull);
    expect(_present(preferences: closedOff, isForeground: false), isNull);
  });

  test('actual active chat is suppressed only while the app is foreground', () {
    expect(_present(activeConversationID: 'single-peer'), isNull);
    expect(_present(activeConversationID: 'another-chat'), isNotNull);
    expect(_present(isForeground: false, activeConversationID: 'single-peer'),
        isNotNull);
  });

  test('single detail uses the conversation name and avatar before sender data',
      () {
    final presentation = _present()!;
    expect(presentation.title, 'Alice remark');
    expect(presentation.body, 'SDK message body');
    expect(presentation.avatarURL, 'https://example.com/conversation.png');
    expect(presentation.senderName, 'Alice');
    expect(presentation.isGroup, isFalse);
    expect(_present(conversation: _conversation()..faceURL = '')!.avatarURL,
        'https://example.com/sender.png');
  });

  test('group detail uses group identity and a sender prefix', () {
    final presentation = _present(conversation: _group())!;
    expect(presentation.title, 'Team');
    expect(presentation.body, 'Alice: SDK message body');
    expect(presentation.avatarURL, 'https://example.com/group.png');
    expect(presentation.isGroup, isTrue);
    expect(_present(conversation: _group()..faceURL = null)!.avatarURL, isNull,
        reason: 'A missing group avatar must not become a sender avatar');
  });

  test('sender mode reveals identity without leaking the SDK body', () {
    const preferences = MessageNotificationPreferences(
        openedPreview: MessageNotificationPreview.sender);
    final single = _present(preferences: preferences)!;
    expect(single.title, 'Alice remark');
    expect(single.body, StrRes.offlineMessage);
    final group = _present(preferences: preferences, conversation: _group())!;
    expect(group.title, 'Team');
    expect(group.body, StrRes.offlineMessage);
    expect(group.body, isNot(contains('Alice:')));
    expect(group.senderName, 'Alice');
  });

  test('anonymous mode removes every display identity field', () {
    final presentation = _present(
        conversation: _group(),
        preferences: const MessageNotificationPreferences(
            openedPreview: MessageNotificationPreview.none))!;
    expect(presentation.title, StrRes.offlineMessage);
    expect(presentation.body, StrRes.offlineMessage);
    expect(presentation.avatarURL, isNull);
    expect(presentation.senderName, isEmpty);
    expect(presentation.isGroup, isFalse);
    expect(presentation.title, isNot(contains('Team')));
  });

  test('background selects closed preview independently of opened preview', () {
    const preferences = MessageNotificationPreferences(
        openedPreview: MessageNotificationPreview.detail,
        closedPreview: MessageNotificationPreview.none);
    expect(_present(preferences: preferences)!.body, 'SDK message body');
    final background = _present(preferences: preferences, isForeground: false)!;
    expect(background.body, StrRes.offlineMessage);
    expect(background.avatarURL, isNull);
  });

  test('private conversation and parsed or raw private messages hide content',
      () {
    final privateConversation = _conversation()..isPrivateChat = true;
    final parsed = _message()
      ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    final raw = _message()..attachedInfo = '{"isPrivateChat":true}';
    for (final foreground in [true, false]) {
      expect(
          _present(isForeground: foreground, conversation: privateConversation)!
              .body,
          StrRes.offlineMessage);
      for (final message in [parsed, raw]) {
        expect(_present(isForeground: foreground, message: message)!.body,
            StrRes.offlineMessage);
      }
    }
  });

  test('reply sound and vibration follow fresh preference snapshots', () {
    final presentation = _present(
        preferences: const MessageNotificationPreferences(
            quickReply: false, messageSoundEnabled: false, vibration: false))!;
    expect(presentation.showReply, isFalse);
    expect(presentation.enableSound, isFalse);
    expect(presentation.enableVibration, isFalse);
    expect(_present()!.showReply, isTrue);
  });

  test(
      'official notification replies are hidden in every preview and app state',
      () {
    for (final conversation in [
      _conversation()..userID = '99Message',
      _conversation()..userID = '99Pay',
      _conversation()..ex = '{"accountType":"official","officialRole":"pay"}',
    ]) {
      for (final foreground in [true, false]) {
        for (final preview in MessageNotificationPreview.values) {
          final presentation = _present(
              conversation: conversation,
              isForeground: foreground,
              preferences: MessageNotificationPreferences(
                  quickReply: true,
                  openedPreview: preview,
                  closedPreview: preview))!;
          expect(presentation.showReply, isFalse);
          if (preview == MessageNotificationPreview.detail) {
            expect(presentation.body, 'SDK message body');
          }
        }
      }
    }
  });

  test('interactive official and group conversations retain quick reply', () {
    for (final conversation in [
      _conversation()..userID = 'assistant',
      _conversation()..ex = '{"accountType":"official"}',
      _conversation()..ex = '{"officialRole":"pay"}',
      _group(),
    ]) {
      expect(
          _present(
                  conversation: conversation,
                  message: _message()..sendID = '99Pay')!
              .showReply,
          isTrue);
    }
  });

  test('SDK media preview preserves localized message-type labels', () {
    final picture = _message()..contentType = MessageType.picture;
    expect(_present(message: picture)!.body, '[${StrRes.picture}]');
    final voice = _message()
      ..contentType = MessageType.voice
      ..soundElem = SoundElem(duration: 8);
    expect(_present(message: voice)!.body, '[${StrRes.voice}] 8″');
    final file = _message()
      ..contentType = MessageType.file
      ..fileElem = FileElem(fileName: 'contract.pdf');
    expect(_present(message: file)!.body, '[${StrRes.file}] contract.pdf');
  });

  test('quoted private content is not copied into the reply preview', () {
    final quote = _message()
      ..contentType = MessageType.quote
      ..quoteElem = QuoteElem(
          text: 'Public reply',
          quoteMessage: _message()
            ..textElem = TextElem(content: 'Private quoted secret')
            ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true));
    expect(_present(message: quote)!.body, 'Public reply');
  });

  test('custom HTML and offline push are not alternative sources of plaintext',
      () {
    final custom = _message()
      ..contentType = MessageType.custom
      ..customElem = CustomElem(
          data: '{"customType":999,"data":{"html":"<b>secret</b>"}}',
          extension: '{"decrypted":"unverified secret"}',
          description: 'unverified body');
    expect(_present(message: custom)!.body, '[${StrRes.unsupportedMessage}]');
    final noText = _message()
      ..textElem = TextElem(content: '')
      ..offlinePush = OfflinePushInfo(
          title: 'Untrusted title',
          desc: 'Unverified offline body',
          ex: '{"decrypted":"secret"}');
    expect(_present(message: noText)!.body, StrRes.offlineMessage);
    expect(_present(message: noText)!.title, 'Alice remark');
  });

  test('presentation is a plain snapshot with no mutable SDK object retained',
      () {
    final message = _message()
      ..textElem = TextElem(content: 'line one\nline two');
    final conversation = _conversation();
    final presentation =
        _present(message: message, conversation: conversation)!;
    message.textElem!.content = 'changed';
    conversation.showName = 'changed';
    expect(presentation.body, 'line one line two');
    expect(presentation.title, 'Alice remark');
  });
}
