import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_loader.dart';
import 'package:openim/services/chat_history_cache.dart';

ConversationInfo _conversation({bool private = false, bool group = false}) =>
    ConversationInfo(
      conversationID: group ? 'sg_group' : 'si_peer',
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : 'peer',
      groupID: group ? 'group' : null,
      isPrivateChat: private,
      unreadCount: 8,
    );

Message _message(String id, int time) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'peer',
      'recvID': 'self',
      'sendTime': time,
      'seq': time,
      'status': MessageStatus.succeeded,
      'isRead': false,
      'textElem': {'content': id},
      'exMap': {'showTime': false},
    });

AdvancedMessage _page(List<Message> messages, {bool isEnd = false}) =>
    AdvancedMessage(messageList: messages, isEnd: isEnd, errCode: 0);

ConversationPeekLoader _loader({
  required Future<AdvancedMessage> Function(
          {required int count, Message? startMsg})
      fetch,
  ConversationInfo? conversation,
}) =>
    ConversationPeekLoader(
      conversation: conversation ?? _conversation(),
      fetch: fetch,
      currentAccountID: () => 'self',
      currentToken: () => 'token',
    );

List<String?> _ids(ConversationPeekLoader loader) =>
    loader.messages.map((message) => message.clientMsgID).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  setUp(ChatHistoryCache.clear);
  tearDown(() {
    ChatHistoryCache.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'real SDK reads latest and older history without marking or clearing unread',
      () async {
    final calls = <Map<String, dynamic>>[];
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      expect(call.method, 'getAdvancedHistoryMessageList');
      calls.add(Map<String, dynamic>.from(call.arguments as Map));
      return jsonEncode(_page([
        _message(
            calls.length == 1 ? 'latest' : 'older', calls.length == 1 ? 2 : 1)
      ], isEnd: calls.length == 2)
          .toJson());
    });
    final conversation = _conversation(group: true);
    final loader = ConversationPeekLoader(
      conversation: conversation,
      currentAccountID: () => 'self',
      currentToken: () => 'token',
    );
    addTearDown(loader.dispose);
    expect(await loader.loadInitial(), isTrue);
    expect(await loader.loadOlder(), isTrue);
    expect(calls.first['conversationID'], 'sg_group');
    expect(calls.first['count'], 30);
    expect(calls.first['startClientMsgID'], '');
    expect(calls.last['startClientMsgID'], 'latest');
    expect(methods,
        ['getAdvancedHistoryMessageList', 'getAdvancedHistoryMessageList']);
    expect(conversation.unreadCount, 8);
    expect(loader.messages.every((message) => message.isRead == false), isTrue);
    expect(_ids(loader), ['older', 'latest']);
    expect(loader.hasMoreOlder, isFalse);
  });

  test(
      'safe cache paints immediately and SDK replaces it with independent clones',
      () async {
    final cached = [for (var i = 1; i <= 40; i++) _message('cached-$i', i)];
    ChatHistoryCache.write('self', 'si_peer', cached);
    final pending = Completer<AdvancedMessage>();
    var reads = 0;
    final loader = _loader(fetch: ({required count, startMsg}) {
      expect(count, 30);
      expect(startMsg, isNull);
      reads++;
      return pending.future;
    });
    addTearDown(loader.dispose);
    final first = loader.loadInitial();
    expect(identical(loader.loadInitial(), first), isTrue);
    expect(identical(loader.loadOlder(), first), isTrue);
    expect(reads, 1);
    expect(loader.loading, isTrue);
    expect(loader.loadingOlder, isFalse);
    expect(loader.loaded, isFalse);
    expect(loader.messages, hasLength(30));
    expect(loader.messages.first.clientMsgID, 'cached-11');
    loader.messages.last.isRead = true;
    loader.messages.last.exMap['showTime'] = true;
    expect(cached.last.isRead, isFalse);
    expect(cached.last.exMap['showTime'], isFalse);

    final fresh = _message('fresh', 41);
    pending.complete(_page([fresh], isEnd: true));
    expect(await first, isTrue);
    expect(_ids(loader), ['fresh']);
    expect(loader.loading, isFalse);
    expect(loader.loaded, isTrue);
    loader.messages.single.isRead = true;
    loader.messages.single.textElem!.content = 'Preview changed';
    expect(fresh.isRead, isFalse);
    expect(fresh.textElem!.content, 'fresh');
    final retained = ChatHistoryCache.read('self', 'si_peer').single;
    expect(retained.isRead, isFalse);
    expect(retained.textElem!.content, 'fresh');
  });

  test('older pages use the raw SDK cursor and deduplicate visible history',
      () async {
    final pending = <Completer<AdvancedMessage>>[];
    final cursors = <String?>[];
    final loader = _loader(fetch: ({required count, startMsg}) {
      cursors.add(startMsg?.clientMsgID);
      final response = Completer<AdvancedMessage>();
      pending.add(response);
      return response.future;
    });
    addTearDown(loader.dispose);
    final typing = _message('typing-boundary', 2)
      ..contentType = MessageType.typing;
    ChatHistoryCache.removeMessage('self', 'removed');
    final first = loader.loadInitial();
    pending.first
        .complete(_page([_message('new', 4), typing, _message('removed', 3)]));
    expect(await first, isTrue);
    expect(_ids(loader), ['new']);
    expect(loader.hasMoreOlder, isTrue);
    final older = loader.loadOlder();
    expect(identical(loader.loadOlder(), older), isTrue);
    expect(loader.loading, isFalse);
    expect(loader.loadingOlder, isTrue);
    expect(cursors, [null, 'typing-boundary']);
    pending.last
        .complete(_page([_message('old', 1), _message('new', 4)], isEnd: true));
    expect(await older, isTrue);
    expect(_ids(loader), ['old', 'new']);
    expect(loader.loadingOlder, isFalse);
    expect(await loader.loadOlder(), isFalse);
    expect(pending, hasLength(2));
    expect(ChatHistoryCache.read('self', 'si_peer').map((m) => m.clientMsgID),
        ['new']);
  });

  test(
      'initial and older failures retain their window and retry the same request',
      () async {
    ChatHistoryCache.write('self', 'si_peer', [_message('cached', 3)]);
    final pending = <Completer<AdvancedMessage>>[];
    final cursors = <String?>[];
    final loader = _loader(fetch: ({required count, startMsg}) {
      cursors.add(startMsg?.clientMsgID);
      final response = Completer<AdvancedMessage>();
      pending.add(response);
      return response.future;
    });
    addTearDown(loader.dispose);
    final initial = loader.loadInitial();
    pending.last.completeError(StateError('offline'));
    expect(await initial, isFalse);
    expect(loader.error, isA<StateError>());
    expect(loader.olderError, isNull);
    expect(loader.loading, isFalse);
    expect(_ids(loader), ['cached']);
    final retry = loader.retry();
    pending.last.complete(_page([_message('latest', 3)]));
    expect(await retry, isTrue);
    expect(loader.error, isNull);
    final older = loader.loadOlder();
    pending.last
        .complete(AdvancedMessage(errCode: 1506, errMsg: 'invalid token'));
    expect(await older, isFalse);
    expect(loader.olderError, isA<StateError>());
    expect(loader.error, isNull);
    expect(_ids(loader), ['latest']);
    final retryOlder = loader.retryOlder();
    pending.last.complete(_page([_message('older', 1)], isEnd: true));
    expect(await retryOlder, isTrue);
    expect(cursors, [null, null, 'latest', 'latest']);
    expect(loader.olderError, isNull);
    expect(_ids(loader), ['older', 'latest']);
  });

  test('successful empty history clears the seed and is distinct from failure',
      () async {
    ChatHistoryCache.write('self', 'si_peer', [_message('stale', 1)]);
    final loader = _loader(
        fetch: ({required count, startMsg}) async => _page([], isEnd: true));
    addTearDown(loader.dispose);
    expect(await loader.loadInitial(), isTrue);
    expect(loader.messages, isEmpty);
    expect(loader.loaded, isTrue);
    expect(loader.error, isNull);
    expect(loader.hasMoreOlder, isFalse);
    expect(ChatHistoryCache.read('self', 'si_peer'), isEmpty);
  });

  for (final serialized in [null, '', 'null', '  null  ', '{}']) {
    test(
        'absent retention metadata preserves cached and fresh replies ($serialized)',
        () async {
      final original = _message('original', 1)..attachedInfo = serialized;
      final reply = _message('reply', 2)
        ..attachedInfo = serialized
        ..contentType = MessageType.quote
        ..quoteElem = QuoteElem(text: 'Reply text', quoteMessage: original);
      ChatHistoryCache.write('self', 'si_peer', [original, reply]);
      final pending = Completer<AdvancedMessage>();
      final loader =
          _loader(fetch: ({required count, startMsg}) => pending.future);
      addTearDown(loader.dispose);
      final initial = loader.loadInitial();
      expect(_ids(loader), ['original', 'reply']);
      pending.complete(_page([original, reply], isEnd: true));
      expect(await initial, isTrue);
      expect(_ids(loader), ['original', 'reply']);
      expect(loader.messages.any(ConversationPeekLoader.containsPrivateContent),
          isFalse);
      expect(ChatHistoryCache.read('self', 'si_peer').length, 2);

      // An empty serialized field cannot override real private metadata.
      original.attachedInfoElem =
          AttachedInfoElem(isPrivateChat: true, burnDuration: 30);
      expect(ConversationPeekLoader.isPrivateMessage(original), isTrue);
      expect(ConversationPeekLoader.containsPrivateContent(reply), isTrue);
    });
  }

  test(
      'private retention metadata never seeds cache and expired SDK content is filtered',
      () async {
    final unreadPrivate = _message('private', 2)
      ..attachedInfo = jsonEncode({'isPrivateChat': true, 'burnDuration': 30});
    expect(ConversationPeekLoader.isPrivateMessage(unreadPrivate), isTrue);
    expect(
        ConversationPeekLoader.isPrivateMessage(
            _message('unknown-retention', 2)..attachedInfo = '{bad metadata'),
        isTrue);
    final expired = _message('expired', 1)
      ..attachedInfoElem = AttachedInfoElem(
          isPrivateChat: true,
          burnDuration: 1,
          hasReadTime: DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch);
    final ordinary = _message('ordinary', 3);
    // Serialized-only metadata can exist in old snapshots; the preview must
    // treat it as private even when the cache predates that normalization.
    ChatHistoryCache.write('self', 'si_peer', [unreadPrivate, ordinary]);
    final pending = Completer<AdvancedMessage>();
    final loader =
        _loader(fetch: ({required count, startMsg}) => pending.future);
    addTearDown(loader.dispose);
    final initial = loader.loadInitial();
    expect(_ids(loader), ['ordinary']);
    pending.complete(_page([expired, unreadPrivate, ordinary], isEnd: true));
    expect(await initial, isTrue);
    expect(_ids(loader), ['private', 'ordinary']);
    final private = loader.messages.first;
    expect(ConversationPeekLoader.isPrivateMessage(private), isTrue);
    expect(private.isRead, isFalse);
    expect(private.hasReadTime, isNull);
    expect(unreadPrivate.attachedInfoElem, isNull);
    expect(ChatHistoryCache.read('self', 'si_peer').map((m) => m.clientMsgID),
        ['ordinary']);

    final privateConversation = _loader(
        conversation: _conversation(private: true),
        fetch: ({required count, startMsg}) async =>
            _page([unreadPrivate], isEnd: true));
    addTearDown(privateConversation.dispose);
    final freshPrivate = privateConversation.loadInitial();
    expect(privateConversation.messages, isEmpty);
    expect(await freshPrivate, isTrue);
    expect(_ids(privateConversation), ['private']);
    expect(ChatHistoryCache.read('self', 'si_peer').map((m) => m.clientMsgID),
        ['ordinary']);
  });

  test('private quote and merge pages stay out of the shared history cache',
      () async {
    final private = _message('private', 1)
      ..attachedInfo = jsonEncode({'isPrivateChat': true, 'burnDuration': 30});
    final quoted = _message('quoted', 2)
      ..contentType = MessageType.quote
      ..quoteElem =
          QuoteElem(text: 'Quoted private content', quoteMessage: private);
    final merged = _message('merged', 3)
      ..contentType = MessageType.merger
      ..mergeElem =
          MergeElem(title: 'Merged private content', multiMessage: [quoted]);
    final ordinary = _message('ordinary', 4);
    ChatHistoryCache.write('self', 'si_peer', [quoted, merged, ordinary]);
    final pending = Completer<AdvancedMessage>();
    final loader =
        _loader(fetch: ({required count, startMsg}) => pending.future);
    addTearDown(loader.dispose);
    final initial = loader.loadInitial();
    expect(_ids(loader), ['ordinary']);
    pending.complete(_page([quoted, merged, ordinary], isEnd: true));
    expect(await initial, isTrue);
    expect(_ids(loader), ['quoted', 'merged', 'ordinary']);
    expect(
        loader.messages
            .take(2)
            .every(ConversationPeekLoader.containsPrivateContent),
        isTrue);
    expect(ChatHistoryCache.read('self', 'si_peer').map((m) => m.clientMsgID),
        ['ordinary']);
    expect(private.isRead, isFalse);
    expect(private.hasReadTime, isNull);
    expect(quoted.quoteElem?.quoteMessage, same(private));
  });

  for (final stop in ['dispose', 'account', 'token', 'epoch', 'conversation']) {
    test('a pending preview cannot restore history after $stop', () async {
      var account = 'self';
      var token = 'token';
      final pending = Completer<AdvancedMessage>();
      final loader = ConversationPeekLoader(
        conversation: _conversation(),
        currentAccountID: () => account,
        currentToken: () => token,
        fetch: ({required count, startMsg}) => pending.future,
      );
      addTearDown(loader.dispose);
      var notifications = 0;
      loader.addListener(() => notifications++);
      final loading = loader.loadInitial();
      switch (stop) {
        case 'dispose':
          loader.dispose();
        case 'account':
          account = 'other';
        case 'token':
          token = 'new-token';
        case 'epoch':
          ChatHistoryCache.clear();
        case 'conversation':
          ChatHistoryCache.removeConversation('self', 'si_peer');
      }
      final beforeReply = notifications;
      pending.complete(_page([_message('late', 1)]));
      expect(await loading, isFalse);
      expect(loader.isCurrent, isFalse);
      expect(loader.messages, isEmpty);
      expect(loader.loading, isFalse);
      expect(loader.loadingOlder, isFalse);
      expect(loader.error, isNull);
      expect(ChatHistoryCache.read('self', 'si_peer'), isEmpty);
      if (stop == 'dispose') expect(notifications, beforeReply);
      expect(await loader.loadInitial(), isFalse);
    });
  }

  test(
      'deletion during a pending read filters the reply without altering SDK objects',
      () async {
    final removed = _message('removed', 1);
    final retained = _message('retained', 2);
    final pending = Completer<AdvancedMessage>();
    final loader =
        _loader(fetch: ({required count, startMsg}) => pending.future);
    addTearDown(loader.dispose);
    final loading = loader.loadInitial();
    ChatHistoryCache.removeMessage('self', 'removed');
    pending.complete(_page([removed, retained], isEnd: true));
    expect(await loading, isTrue);
    expect(_ids(loader), ['retained']);
    expect(removed.isRead, isFalse);
    expect(retained.isRead, isFalse);
    expect(ChatHistoryCache.read('self', 'si_peer').map((m) => m.clientMsgID),
        ['retained']);
  });
}
