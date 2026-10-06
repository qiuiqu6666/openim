import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/summary/conversation_latest_message_text.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _message(int type, [Map<String, dynamic> elements = const {}]) =>
    Message.fromJson({
      'clientMsgID': 'latest',
      'contentType': type,
      'sendID': 'peer',
      'senderNickname': '小林',
      ...elements,
    });

ConversationInfo _conversation(Message? message, {bool group = false}) =>
    ConversationInfo(
      conversationID: group ? 'sg_team' : 'si_peer',
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      latestMsg: message,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.testMode = true;
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
    OpenIM.iMManager.userID = 'self';
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });

  tearDown(() {
    Get.reset();
    OpenIM.iMManager.userID = 'self';
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
    test('formats supported latest message types in $locale', () {
      Get.locale = locale;
      final examples = <(Message, String)>[
        (
          _message(MessageType.text, {
            'textElem': {'content': 'hello\nworld'}
          }),
          'hello world'
        ),
        (
          _message(MessageType.advancedText, {
            'advancedTextElem': {'text': 'rich'}
          }),
          'rich'
        ),
        (
          _message(MessageType.atText, {
            'atTextElem': {
              'text': '@peer @atAllTag hello',
              'atUsersInfo': [
                {'atUserID': 'peer', 'groupNickname': '小林'}
              ],
            },
          }),
          '@小林 @${StrRes.everyone} hello'
        ),
        (_message(MessageType.picture), '[${StrRes.picture}]'),
        (_message(MessageType.video), '[${StrRes.video}]'),
        (
          _message(MessageType.voice, {
            'soundElem': {'duration': 7}
          }),
          '[${StrRes.voice}] 7″'
        ),
        (
          _message(MessageType.file, {
            'fileElem': {'fileName': 'report.pdf'}
          }),
          '[${StrRes.file}] report.pdf'
        ),
        (
          _message(MessageType.card, {
            'cardElem': {'nickname': '张三'}
          }),
          '[${StrRes.carte}]张三'
        ),
        (
          _message(MessageType.quote, {
            'quoteElem': {'text': 'reply'}
          }),
          'reply'
        ),
        (
          _message(MessageType.merger, {
            'mergeElem': {'title': 'A and B'}
          }),
          '[${StrRes.chatRecord}] A and B'
        ),
        (
          _message(MessageType.location, {
            'locationElem': {'description': 'Office'}
          }),
          '[${StrRes.toolboxLocation}] Office'
        ),
        (_message(MessageType.customFace), '[${StrRes.emoji}]'),
        (_message(999), '[${StrRes.unsupportedMessage}]'),
      ];
      for (final (message, expected) in examples) {
        expect(conversationLatestMessageText(_conversation(message)), expected,
            reason: 'contentType=${message.contentType}');
      }
    });
  }

  test('keeps canonical group sender prefix and own-message formatting', () {
    final message = _message(MessageType.text, {
      'textElem': {'content': 'hello'}
    });
    final group = _conversation(message, group: true);
    expect(conversationLatestMessageText(group), '小林: hello ');
    // Legacy group conversations remain readable in existing databases.
    // ignore: deprecated_member_use
    group.conversationType = ConversationType.group;
    expect(conversationLatestMessageText(group), '小林: hello ');
    message.sendID = 'self';
    expect(conversationLatestMessageText(group), 'hello');
    message.sendID = 'peer';
    expect(conversationLatestMessageText(_conversation(message)), 'hello');
  });

  test('notification summary has no extra group sender prefix', () {
    final notification =
        _message(MessageType.groupInfoSetAnnouncementNotification, {
      'notificationElem': {
        'detail': jsonEncode({
          'group': {'groupID': 'team', 'notification': '公告正文'}
        })
      }
    });
    expect(
        conversationLatestMessageText(_conversation(notification, group: true)),
        '公告正文');
    expect(conversationLatestMessageText(_conversation(null)), '');
    expect(
        conversationLatestMessageText(
            _conversation(_message(MessageType.text))),
        '[${StrRes.unsupportedMessage}]');
  });

  test('main conversation keeps draft priority while shared summary ignores it',
      () {
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
    Get.put<HomeLogic>(_Home());
    // Use the real formatter without starting SDK loading or subscriptions.
    final logic = ConversationLogic();
    addTearDown(logic.onClose);
    final conversation = _conversation(_message(MessageType.text, {
      'textElem': {'content': 'sent text'}
    }));

    for (final draft in [
      'draft text',
      jsonEncode({'text': 'draft text'})
    ]) {
      conversation.draftText = draft;
      expect(logic.getContent(conversation), 'draft text');
      expect(logic.getPrefixTag(conversation), '[${StrRes.draftText}]');
      expect(conversationPrefixTag(conversation), '[${StrRes.draftText}]');
      expect(conversationLatestMessageText(conversation), 'sent text');
    }
    for (final draft in [
      null,
      '',
      jsonEncode({'text': ''})
    ]) {
      conversation.draftText = draft;
      expect(logic.getContent(conversation), 'sent text');
    }
    conversation
      ..latestMsg = null
      ..draftText = 'unsent only';
    expect(logic.getContent(conversation), 'unsent only');
    expect(conversationLatestMessageText(conversation), '');
  });

  test('shared prefix gives draft precedence over group announcement', () {
    final conversation = _conversation(null, group: true);
    expect(conversationPrefixTag(conversation), isNull);
    conversation.groupAtType = GroupAtType.groupNotification;
    expect(conversationPrefixTag(conversation), '[${StrRes.groupAc}]');
    conversation.draftText = 'draft';
    expect(conversationPrefixTag(conversation), '[${StrRes.draftText}]');
    conversation.draftText = '';
    expect(conversationPrefixTag(conversation), '[${StrRes.groupAc}]');
  });
}
