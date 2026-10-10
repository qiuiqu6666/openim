import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/message_notification_policy.dart';
import 'package:openim/core/notifications/message_notification_preferences.dart';
import 'package:openim/pages/conversation/drafts/conversation_draft_text.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_loader.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim/services/chat_message_sender.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import '../../../support/unicode/unicode_samples.dart';

const _channel = MethodChannel('unicode-sdk-roundtrip');

/// Exercise the production SDK Dart manager and Flutter's method codec. The
/// native handler is a controlled JSON/UTF-8 boundary, not a real SDK database
/// or a remote server; those require separate device/deployment verification.
class _UnicodeBridge {
  final manager = MessageManager(_channel);
  final conversations = ConversationManager(_channel);
  final calls = <MethodCall>[];
  final messages = <Map<String, dynamic>>[];
  String draft = '';
  int _nextID = 0;

  Map<String, dynamic> _jsonMap(Object? value) =>
      Map<String, dynamic>.from(jsonDecode(utf8.decode(utf8.encode(
        jsonEncode(value),
      ))) as Map);

  Map<String, dynamic> _message(int type, Map<String, Object?> elements) => {
        'clientMsgID': 'unicode-${_nextID++}',
        'contentType': type,
        'sendID': 'self',
        'recvID': 'peer',
        'sessionType': ConversationType.single,
        'status': MessageStatus.succeeded,
        'sendTime': 1,
        'seq': _nextID,
        ...elements,
      };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final args = Map<String, dynamic>.from(call.arguments as Map);
    switch (call.method) {
      case 'createTextMessage':
        return jsonEncode(_message(MessageType.text, {
          'textElem': {'content': args['text']},
        }));
      case 'createQuoteMessage':
        return jsonEncode(_message(MessageType.quote, {
          'quoteElem': {
            'text': args['quoteText'],
            'quoteMessage': _jsonMap(args['quoteMessage']),
          },
        }));
      case 'createTextAtMessage':
        return jsonEncode(_message(MessageType.atText, {
          'atTextElem': {
            'text': args['text'],
            'atUserList': args['atUserIDList'],
            'atUsersInfo': args['atUserInfoList'],
            'quoteMessage': _jsonMap(args['quoteMessage']),
          },
        }));
      case 'createForwardMessage':
        return jsonEncode(_jsonMap(args['message'])
          ..['clientMsgID'] = 'unicode-${_nextID++}');
      case 'createMergerMessage':
        return jsonEncode(_message(MessageType.merger, {
          'mergeElem': {
            'title': args['title'],
            'abstractList': args['summaryList'],
            'multiMessage': args['messageList'],
          },
        }));
      case 'sendMessage':
        final sent = _jsonMap(args['message'])
          ..['offlinePush'] = args['offlinePushInfo']
          ..['status'] = MessageStatus.succeeded;
        messages.add(_jsonMap(sent));
        return jsonEncode(sent);
      case 'insertSingleMessageToLocalStorage':
        final stored = _jsonMap(args['message']);
        messages.add(stored);
        return jsonEncode(stored);
      case 'setConversationDraft':
        draft = args['draftText'] as String;
        return null;
      case 'getOneConversation':
        return jsonEncode({
          'conversationID': 'si_peer',
          'conversationType': ConversationType.single,
          'userID': 'peer',
          'unreadCount': 0,
          'draftText': draft,
          'latestMsg': messages.isEmpty ? null : jsonEncode(messages.last),
        });
      case 'getAdvancedHistoryMessageList':
        return jsonEncode({
          'messageList': messages,
          'isEnd': true,
          'errCode': 0,
        });
      case 'searchLocalMessages':
        return jsonEncode({
          'totalCount': messages.length,
          'searchResultItems': [
            {
              'conversationID': 'si_peer',
              'messageCount': messages.length,
              'messageList': messages,
            },
          ],
        });
      default:
        throw StateError('Unexpected SDK call ${call.method}');
    }
  }
}

void _sameSequence(String? actual, String expected) {
  expect(actual, expected);
  // Equality on code units makes selector/joiner/tag loss and normalization
  // explicit even when two strings render identically on the test host.
  expect(actual?.codeUnits, orderedEquals(expected.codeUnits));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _UnicodeBridge bridge;

  setUp(() {
    bridge = _UnicodeBridge();
    ChatHistoryCache.clear();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, bridge.handle);
  });
  tearDown(() {
    ChatHistoryCache.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final sample in unicodeSamples) {
    test(
        '${sample.name}: draft, SDK send, history, cache and preview retain data',
        () async {
      final text = sample.text;
      final draft = jsonEncode({
        'text': text,
        'mentions': {'peer': text},
      });
      await bridge.conversations
          .setConversationDraft(conversationID: 'si_peer', draftText: draft);
      final restored = await bridge.conversations.getOneConversation(
          sourceID: 'peer', sessionType: ConversationType.single);
      _sameSequence(conversationDraftText(restored.draftText), text);
      _sameSequence(
          (jsonDecode(restored.draftText!) as Map)['mentions']['peer'], text);

      final message = await bridge.manager.createTextMessage(text: text);
      message.senderNickname = text;
      message.localEx = jsonEncode({'transcription': text});
      message.ex = jsonEncode({'original': text});
      final sender = ChatMessageSender(
        accountProvider: () => 'self',
        transport: (outgoing, target) => bridge.manager.sendMessage(
          message: outgoing,
          userID: target.userID,
          offlinePushInfo: OfflinePushInfo(title: text, desc: text, ex: text),
        ),
      );
      final sent = await sender.send(message,
          const FavoriteTarget(conversationID: 'si_peer', userID: 'peer'));
      expect(sent.isSuccess, isTrue);
      _sameSequence(message.textElem?.content, text);
      _sameSequence(message.senderNickname, text);
      _sameSequence(message.offlinePush?.title, text);
      _sameSequence(message.offlinePush?.desc, text);
      _sameSequence(
          (jsonDecode(message.localEx!) as Map)['transcription'], text);
      _sameSequence((jsonDecode(message.ex!) as Map)['original'], text);

      final history = await bridge.manager
          .getAdvancedHistoryMessageList(conversationID: 'si_peer', count: 40);
      _sameSequence(history.messageList!.single.textElem?.content, text);
      ChatHistoryCache.write('self', 'si_peer', history.messageList!);
      _sameSequence(
          ChatHistoryCache.read('self', 'si_peer').single.textElem?.content,
          text);
      final loader = ConversationPeekLoader(
        conversation: restored,
        currentAccountID: () => 'self',
        currentToken: () => 'test-session',
        fetch: ({required count, startMsg}) => bridge.manager
            .getAdvancedHistoryMessageList(
                conversationID: 'si_peer', count: count, startMsg: startMsg),
      );
      addTearDown(loader.dispose);
      expect(await loader.loadInitial(), isTrue);
      _sameSequence(loader.messages.single.textElem?.content, text);
      _sameSequence(loader.messages.single.senderNickname, text);
      expect(identical(loader.messages.single, message), isFalse);

      final search = await bridge.manager
          .searchLocalMessages(conversationID: 'si_peer', keywordList: [text]);
      final filter = (bridge.calls.last.arguments as Map)['filter'] as Map;
      _sameSequence((filter['keywordList'] as List).single as String, text);
      _sameSequence(
          search
              .searchResultItems!.single.messageList!.single.textElem?.content,
          text);
    });

    test(
        '${sample.name}: quote, mention, forward and merged models retain data',
        () async {
      final text = sample.text;
      final original = await bridge.manager.createTextMessage(text: text);
      original.senderNickname = text;
      final quote = await bridge.manager
          .createQuoteMessage(text: text, quoteMsg: original);
      _sameSequence(quote.quoteElem?.text, text);
      _sameSequence(quote.quoteElem?.quoteMessage?.textElem?.content, text);
      _sameSequence(quote.quoteElem?.quoteMessage?.senderNickname, text);
      final mention = await bridge.manager.createTextAtMessage(
        text: text,
        atUserIDList: ['peer'],
        atUserInfoList: [AtUserInfo(atUserID: 'peer', groupNickname: text)],
        quoteMessage: quote,
      );
      _sameSequence(mention.atTextElem?.text, text);
      _sameSequence(
          mention.atTextElem?.atUsersInfo?.single.groupNickname, text);
      _sameSequence(mention.atTextElem?.quoteMessage?.quoteElem?.text, text);
      final forwarded =
          await bridge.manager.createForwardMessage(message: mention);
      _sameSequence(forwarded.atTextElem?.text, text);
      _sameSequence(
          forwarded.atTextElem?.atUsersInfo?.single.groupNickname, text);
      final merged = await bridge.manager.createMergerMessage(
          messageList: [original, quote, forwarded],
          title: text,
          summaryList: [text]);
      _sameSequence(merged.mergeElem?.title, text);
      _sameSequence(merged.mergeElem?.abstractList?.single, text);
      _sameSequence(merged.mergeElem?.multiMessage?[0].textElem?.content, text);
      _sameSequence(merged.mergeElem?.multiMessage?[1].quoteElem?.text, text);
      _sameSequence(merged.mergeElem?.multiMessage?[2].atTextElem?.text, text);
      final local = await bridge.manager.insertSingleMessageToLocalStorage(
          message: merged, senderID: 'self', receiverID: 'peer');
      _sameSequence(local.mergeElem?.title, text);
      _sameSequence(
          local.mergeElem?.multiMessage?[1].quoteElem?.quoteMessage?.textElem
              ?.content,
          text);
    });
  }

  test(
      'profile, remark, group name, announcement and member models keep Unicode',
      () {
    final text = unicodeSamples.map((sample) => sample.text).join(' / ');
    Map<String, dynamic> roundtrip(Map<String, dynamic> value) =>
        Map<String, dynamic>.from(
            jsonDecode(utf8.decode(utf8.encode(jsonEncode(value)))) as Map);
    final user = UserInfo.fromJson(roundtrip(
        UserInfo(userID: 'peer', nickname: text, remark: text, ex: text)
            .toJson()));
    _sameSequence(user.nickname, text);
    _sameSequence(user.remark, text);
    _sameSequence(user.ex, text);
    final group = GroupInfo.fromJson(roundtrip(GroupInfo(
            groupID: 'team',
            groupName: text,
            notification: text,
            introduction: text)
        .toJson()));
    _sameSequence(group.groupName, text);
    _sameSequence(group.notification, text);
    _sameSequence(group.introduction, text);
    final member = GroupMembersInfo.fromJson(roundtrip(
        GroupMembersInfo(groupID: 'team', userID: 'peer', nickname: text)
            .toJson()));
    _sameSequence(member.nickname, text);
  });

  test('notification presentation and clipboard preserve complete sequences',
      () async {
    final text = unicodeSamples.map((sample) => sample.text).join(' / ');
    final message = Message(
        clientMsgID: 'notification-unicode',
        contentType: MessageType.text,
        sessionType: ConversationType.superGroup,
        groupID: 'team',
        sendID: 'peer',
        senderNickname: text,
        textElem: TextElem(content: text));
    final presentation = MessageNotificationPolicy.present(
        message: message,
        conversation: ConversationInfo(
            conversationID: 'sg_team',
            conversationType: ConversationType.superGroup,
            groupID: 'team',
            showName: text),
        currentUserID: 'self',
        isForeground: true,
        preferences: const MessageNotificationPreferences());
    _sameSequence(presentation?.title, text);
    _sameSequence(presentation?.senderName, text);
    _sameSequence(presentation?.body, '$text: $text');

    String? clipboard;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
        return null;
      }
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      throw StateError('Unexpected platform call ${call.method}');
    });
    await Clipboard.setData(ClipboardData(text: text));
    _sameSequence((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
  });

  test('notification preview keeps a whitespace base with a combining mark',
      () {
    const text = ' \u0301';
    final presentation = MessageNotificationPolicy.present(
        message: Message(
            clientMsgID: 'combining-notification',
            contentType: MessageType.text,
            sessionType: ConversationType.single,
            sendID: 'peer',
            senderNickname: text,
            textElem: TextElem(content: text)),
        conversation: ConversationInfo(
            conversationID: 'si_peer',
            conversationType: ConversationType.single,
            userID: 'peer',
            showName: text),
        currentUserID: 'self',
        isForeground: true,
        preferences: const MessageNotificationPreferences());
    _sameSequence(presentation?.title, text);
    _sameSequence(presentation?.senderName, text);
    _sameSequence(presentation?.body, text);
  });
}
