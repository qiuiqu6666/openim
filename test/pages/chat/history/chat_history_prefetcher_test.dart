import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/services/chat_history_cache.dart';

ConversationInfo conversation({bool private = false}) => ConversationInfo(
    conversationID: 'chat', userID: 'peer', isPrivateChat: private);
AdvancedMessage page(String id) => AdvancedMessage(
    messageList: [Message(clientMsgID: id)], isEnd: true, errCode: 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  test('local warming starts before remote work and never blocks navigation',
      () async {
    final local = Completer<AdvancedMessage>();
    final remote = Completer<AdvancedMessage>();
    final events = <String>[];
    final prefetcher = ChatHistoryPrefetcher(
        accountID: () => 'me',
        token: () => 't',
        epoch: () => 0,
        fetchLocalWindow: (_, __) {
          events.add('local');
          return local.future;
        },
        fetch: (_, __) {
          events.add('remote');
          return remote.future;
        });
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    events.add('navigation');
    expect(events, ['local', 'remote', 'navigation']);
    final route = prefetcher.readLatest(conversation());
    remote.complete(page('remote'));
    expect((await route).messageList!.single.clientMsgID, 'remote');
    local.complete(page('local'));
    await Future<void>.delayed(Duration.zero);
  });

  test(
      'private chats never warm local messages and speculative work is bounded',
      () async {
    final local = Completer<AdvancedMessage>();
    final remote = Completer<AdvancedMessage>();
    var localCalls = 0;
    var remoteCalls = 0;
    final prefetcher = ChatHistoryPrefetcher(
        accountID: () => 'me',
        token: () => 't',
        epoch: () => 0,
        fetchLocalWindow: (_, __) {
          localCalls++;
          return local.future;
        },
        fetch: (_, __) {
          remoteCalls++;
          return remote.future;
        });
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation(private: true));
    expect(localCalls, 0);
    expect(remoteCalls, 0);
    for (var i = 0; i < 100; i++) {
      prefetcher.prepare(ConversationInfo(conversationID: 'chat-$i'));
    }
    expect(localCalls, 2);
    expect(remoteCalls, 2);
    local.complete(page('local'));
    remote.complete(page('remote'));
    await Future<void>.delayed(Duration.zero);
  });

  for (final versioned in [false, true]) {
    test('delivery before route claims preparation (versioned: $versioned)',
        () async {
      final pending = Completer<AdvancedMessage>();
      var reads = 0;
      final prefetcher = ChatHistoryPrefetcher(
        accountID: () => 'me',
        token: () => 'token',
        epoch: () => 0,
        fetch: (_, __) =>
            ++reads == 1 ? pending.future : Future.value(page('fresh')),
      );
      addTearDown(prefetcher.clear);
      prefetcher.prepare(conversation());
      for (var i = 0; i < 100; i++) {
        ChatHistoryCache.receivedMessage();
        prefetcher.prepare(conversation());
      }
      final route = prefetcher.readLatest(conversation());
      expect(reads, 1);
      final prepared = page('prepared');
      if (versioned) {
        prepared.window = MessageWindow.fromJson({
          'version': 1,
          'conversationID': 'chat',
          'lowerBound': 1,
          'targetWatermark': 1,
          'covered': [
            [1, 1]
          ],
          'missing': [],
          'publishable': true,
          'visibilityKey': '1:1:false',
          'snapshotRevision': 'fixed-window',
          'readiness': 'ready',
          'coverageStatus': 'covered',
        });
      }
      pending.complete(prepared);
      expect((await route).messageList!.single.clientMsgID,
          versioned ? 'prepared' : 'fresh');
      expect(reads, versioned ? 1 : 2);
    });
  }

  test('delivery after preparation invalidates a full but stale first page',
      () async {
    final pending = Completer<AdvancedMessage>();
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      fetch: (_, __) =>
          ++reads == 1 ? pending.future : Future.value(page('new')),
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    final route = prefetcher.readLatest(conversation());
    ChatHistoryCache.receivedMessage();
    pending.complete(page('old'));
    expect((await route).messageList!.single.clientMsgID, 'new');
    expect(reads, 2);
  });

  test('navigation and route share one pending native query', () async {
    final pending = Completer<AdvancedMessage>();
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      fetch: (_, __) {
        reads++;
        return pending.future;
      },
      isRemoved: (_, __) => false,
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    prefetcher.prepare(conversation());
    final route = prefetcher.readLatest(conversation());
    expect(reads, 1);
    pending.complete(page('first'));
    expect((await route).messageList!.single.clientMsgID, 'first');
  });

  test('overlapping route reads reuse an in-flight query for the same session',
      () async {
    final pending = Completer<AdvancedMessage>();
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
        accountID: () => 'me',
        token: () => 'token',
        epoch: () => 0,
        fetch: (_, __) {
          reads++;
          return pending.future;
        });
    addTearDown(prefetcher.clear);
    final first = prefetcher.readLatest(conversation());
    final second = prefetcher.readLatest(conversation());
    expect(reads, 1);
    pending.complete(page('latest'));
    expect((await first).messageList!.single.clientMsgID, 'latest');
    expect((await second).messageList!.single.clientMsgID, 'latest');
  });

  test('a completed result is transferred once, refresh reads afresh',
      () async {
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      fetch: (_, __) async => page('read-${++reads}'),
      isRemoved: (_, __) => false,
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    await Future<void>.delayed(Duration.zero);
    expect(
        (await prefetcher.readLatest(conversation()))
            .messageList!
            .single
            .clientMsgID,
        'read-1');
    expect(
        (await prefetcher.readLatest(conversation()))
            .messageList!
            .single
            .clientMsgID,
        'read-2');
  });

  test('account and token changes invalidate a transferred pending result',
      () async {
    for (final changeAccount in [false, true]) {
      var account = 'first';
      var token = 'original';
      final pending = Completer<AdvancedMessage>();
      final prefetcher = ChatHistoryPrefetcher(
        accountID: () => account,
        token: () => token,
        epoch: () => 0,
        fetch: (_, __) => pending.future,
        isRemoved: (_, __) => false,
      );
      addTearDown(prefetcher.clear);
      prefetcher.prepare(conversation());
      final result = prefetcher.readLatest(conversation());
      final invalid = expectLater(result, throwsStateError);
      if (changeAccount) {
        account = 'second';
      } else {
        token = 'renewed';
      }
      pending.complete(page('old-message'));
      await invalid;
    }
  });

  test('clearing history during preparation forces a fresh native query',
      () async {
    var epoch = 0;
    var reads = 0;
    final pending = Completer<AdvancedMessage>();
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => epoch,
      fetch: (_, __) =>
          ++reads == 1 ? pending.future : Future.value(page('fresh')),
      isRemoved: (_, __) => false,
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    final result = prefetcher.readLatest(conversation());
    epoch++;
    pending.complete(page('cleared'));
    expect((await result).messageList!.single.clientMsgID, 'fresh');
    expect(reads, 2);
  });

  test('a message deleted before route entry is not resurrected', () async {
    final deleted = <String>{};
    final pending = Completer<AdvancedMessage>();
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      fetch: (_, __) => pending.future,
      isRemoved: (_, id) => deleted.contains(id),
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    final result = prefetcher.readLatest(conversation());
    deleted.add('deleted');
    pending.complete(page('deleted'));
    expect((await result).messageList, isEmpty);
  });

  test('private conversations always read directly from the SDK', () async {
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      fetch: (_, __) async => page('read-${++reads}'),
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation(private: true));
    expect(reads, 0);
    await prefetcher.readLatest(conversation(private: true));
    await prefetcher.readLatest(conversation(private: true));
    expect(reads, 2);
  });

  test('clearing this conversation discards a transferred old page', () async {
    var revision = 0;
    var reads = 0;
    final pending = Completer<AdvancedMessage>();
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      conversationRevision: (_, __) => revision,
      fetch: (_, __) {
        reads++;
        return pending.future;
      },
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    final route = prefetcher.readLatest(conversation());
    revision++;
    pending.complete(page('cleared'));
    expect((await route).messageList, isEmpty);
    expect(reads, 1);
  });

  test('global cleanup reads afresh even after a conversation revision existed',
      () async {
    ChatHistoryCache.removeConversation('me', 'chat');
    final pending = Completer<AdvancedMessage>();
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => ChatHistoryCache.epoch,
      fetch: (_, __) =>
          ++reads == 1 ? pending.future : Future.value(page('fresh')),
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    final result = prefetcher.readLatest(conversation());
    ChatHistoryCache.clear();
    pending.complete(page('cleared'));
    expect((await result).messageList!.single.clientMsgID, 'fresh');
    expect(reads, 2);
  });

  for (final alreadyClaimed in [false, true]) {
    test('bulk deletion re-reads an old page (claimed: $alreadyClaimed)',
        () async {
      final pending = Completer<AdvancedMessage>();
      var reads = 0;
      final prefetcher = ChatHistoryPrefetcher(
        accountID: () => 'me',
        token: () => 'token',
        epoch: () => ChatHistoryCache.epoch,
        fetch: (_, __) =>
            ++reads == 1 ? pending.future : Future.value(page('fresh')),
      );
      addTearDown(prefetcher.clear);
      prefetcher.prepare(conversation());
      final claimed =
          alreadyClaimed ? prefetcher.readLatest(conversation()) : null;
      for (var i = 0; i < 1025; i++) {
        ChatHistoryCache.removeMessage('me', 'deleted-$i');
      }
      final result = claimed ?? prefetcher.readLatest(conversation());
      pending.complete(page('deleted-0'));
      expect((await result).messageList!.single.clientMsgID, 'fresh');
      expect(reads, 2);
      expect(ChatHistoryCache.canSeedLatest, isFalse);
    });
  }

  testWidgets('cancelled navigation expires its prepared result',
      (tester) async {
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      fetch: (_, __) async => page('read-${++reads}'),
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    await tester.pump(const Duration(seconds: 3));
    await prefetcher.readLatest(conversation());
    expect(reads, 2);
  });

  test('abandoned preparation errors are observed and can be retried',
      () async {
    var reads = 0;
    final prefetcher = ChatHistoryPrefetcher(
      accountID: () => 'me',
      token: () => 'token',
      epoch: () => 0,
      fetch: (_, __) async {
        if (++reads == 1) throw StateError('SDK busy');
        return page('retried');
      },
      isRemoved: (_, __) => false,
    );
    addTearDown(prefetcher.clear);
    prefetcher.prepare(conversation());
    await Future<void>.delayed(Duration.zero);
    expect(
        (await prefetcher.readLatest(conversation()))
            .messageList!
            .single
            .clientMsgID,
        'retried');
    expect(reads, 2);
  });
}
