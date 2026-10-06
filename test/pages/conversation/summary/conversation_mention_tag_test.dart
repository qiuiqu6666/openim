import 'dart:ui';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/summary/conversation_latest_message_text.dart';
import 'package:openim_common/openim_common.dart';

ConversationInfo _conversation({bool group = true}) => ConversationInfo(
      conversationID: group ? 'sg_team' : 'si_peer',
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.testMode = true;
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
    OpenIM.iMManager.userID = 'self';
  });

  tearDown(() {
    Get.reset();
    OpenIM.iMManager.userID = 'self';
  });

  test('mention tags localize all three SDK states with all before me', () {
    final conversation = _conversation();
    for (final (locale, me, all) in [
      (const Locale('zh', 'CN'), '[有人@我]', '[@所有人]'),
      (const Locale('en', 'US'), '[Someone @ me]', '[@Everyone]'),
    ]) {
      Get.locale = locale;
      expect('[${StrRes.someoneMentionMe}]', me);
      expect('[@${StrRes.everyone}]', all);
      for (final (type, expected) in [
        (GroupAtType.atMe, me),
        (GroupAtType.atAll, all),
        (GroupAtType.atAllAtMe, '$all$me'),
      ]) {
        conversation.groupAtType = type;
        expect(conversationMentionTag(conversation), expected,
            reason: '$locale groupAtType=$type');
      }
    }
  });

  test('mention survives zero unread and a newer ordinary message with a draft',
      () {
    final conversation = _conversation()
      ..latestMsg = Message.fromJson({
        'contentType': MessageType.atText,
        'atTextElem': {'text': '@self hello'},
      })
      ..groupAtType = GroupAtType.atMe
      ..unreadCount = 0;
    expect(conversationMentionTag(conversation), '[有人@我]');
    expect(conversationPrefixTag(conversation), isNull);
    conversation
      ..latestMsg = Message.fromJson({
        'contentType': MessageType.text,
        'senderNickname': '小林',
        'sendID': 'peer',
        'sendTime': 200,
        'seq': 20,
        'textElem': {'content': 'newer ordinary message'},
      })
      ..latestMsgSendTime = 200
      ..draftText = 'my unfinished draft';
    expect(conversationMentionTag(conversation), '[有人@我]');
    expect(conversationPrefixTag(conversation), '[${StrRes.draftText}]');
    expect(conversationLatestMessageText(conversation),
        '小林: newer ordinary message ');
    expect(conversation.groupAtType, GroupAtType.atMe);
    expect(conversation.unreadCount, 0);
    expect(conversation.draftText, 'my unfinished draft');
  });

  test('non-mention states and single chats never acquire a mention tag', () {
    final group = _conversation();
    for (final type in [
      null,
      GroupAtType.atNormal,
      GroupAtType.groupNotification,
      7,
    ]) {
      group.groupAtType = type;
      expect(conversationMentionTag(group), isNull,
          reason: 'groupAtType=$type');
      expect(conversationPrefixTag(group),
          type == GroupAtType.groupNotification ? '[${StrRes.groupAc}]' : null);
    }
    final single = _conversation(group: false);
    for (final type in [
      GroupAtType.atMe,
      GroupAtType.atAll,
      GroupAtType.atAllAtMe,
    ]) {
      single.groupAtType = type;
      expect(conversationMentionTag(single), isNull,
          reason: 'single chat type=$type');
    }
  });
}
