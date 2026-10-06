import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_controller.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/stickers/sticker_video_message.dart';

typedef SearchCall = ({
  String conversationID,
  ChatHistorySearchQuery query,
  int pageIndex,
  int count,
});

class FakeSearchSource implements ChatHistorySearchSource {
  FakeSearchSource(this.respond);
  final Future<List<Message>> Function(SearchCall) respond;
  final calls = <SearchCall>[];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) {
    final call = (
      conversationID: conversationID,
      query: query,
      pageIndex: pageIndex,
      count: count,
    );
    calls.add(call);
    return respond(call);
  }
}

Message message(String id, {String sender = 'alice', DateTime? time}) =>
    Message(
      clientMsgID: id,
      sendID: sender,
      contentType: MessageType.text,
      sendTime: time?.millisecondsSinceEpoch,
    );

List<Message> page(String prefix, {String sender = 'alice', int count = 30}) =>
    List.generate(count, (index) => message('$prefix-$index', sender: sender));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('query parameters', () {
    test('keywordless searches have supported nonempty type filters', () {
      const all = ChatHistorySearchQuery();
      const sender = ChatHistorySearchQuery(senderIDs: ['alice']);
      expect(all.sdkMessageTypes, isNotEmpty);
      expect(
          sender.sdkMessageTypes,
          containsAll([
            MessageType.text,
            MessageType.picture,
            MessageType.voice,
            MessageType.video,
            MessageType.file,
            MessageType.atText,
            MessageType.merger,
            MessageType.card,
            MessageType.location,
            MessageType.custom,
            MessageType.quote,
          ]));
      expect(sender.sdkMessageTypes, isNot(contains(MessageType.typing)));
      expect(sender.sdkMessageTypes, isNot(contains(MessageType.advancedText)));
      expect(const ChatHistorySearchQuery(keyword: 'hello').sdkMessageTypes,
          isEmpty);
    });

    test('dates include the selected local day but exclude next midnight', () {
      final query = ChatHistorySearchQuery(
        startDate: DateTime(2026, 12, 31, 10, 30),
        endDate: DateTime(2026, 12, 31, 20, 40),
      ).snapshot();
      final start = DateTime(2026, 12, 31);
      final end = DateTime(2027, 1, 1);
      expect(query.localStart, start);
      expect(query.localEndExclusive, end);
      expect(query.searchTimePosition, end.millisecondsSinceEpoch ~/ 1000);
      expect(query.searchTimePeriod, end.difference(start).inSeconds);
      expect(query.accepts(message('start', time: start)), isTrue);
      expect(
          query.accepts(message('last',
              time: end.subtract(const Duration(milliseconds: 1)))),
          isTrue);
      expect(query.accepts(message('end', time: end)), isFalse);
      expect(query.accepts(message('no-time')), isFalse);
    });

    test('date range supports calendar month boundaries and validates order',
        () {
      final query = ChatHistorySearchQuery(
        startDate: DateTime(2024, 2, 28),
        endDate: DateTime(2024, 2, 29),
      ).snapshot();
      expect(query.localEndExclusive, DateTime(2024, 3, 1));
      expect(() => ChatHistorySearchQuery(startDate: DateTime(2026)).snapshot(),
          throwsArgumentError);
      expect(
          () => ChatHistorySearchQuery(
                startDate: DateTime(2026, 10, 2),
                endDate: DateTime(2026, 10, 1),
              ).snapshot(),
          throwsArgumentError);
    });

    test('snapshots normalize filters and isolate them from caller mutations',
        () {
      final types = <int>[MessageType.file, MessageType.file];
      final senders = [' alice ', '', 'alice'];
      final query = ChatHistorySearchQuery(
        keyword: ' invoice ',
        messageTypes: types,
        senderIDs: senders,
      ).snapshot();
      types.clear();
      senders.clear();
      expect(query.keyword, 'invoice');
      expect(query.messageTypes, [MessageType.file]);
      expect(query.senderIDs, ['alice']);
      expect(() => query.senderIDs.add('bob'), throwsUnsupportedError);
    });
  });

  group('search state', () {
    test('initial idle becomes loading then successful empty', () async {
      final response = Completer<List<Message>>();
      final source = FakeSearchSource((_) => response.future);
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      expect(controller.hasSearched, isFalse);
      expect(controller.hasMore, isFalse);
      final future = controller.search(const ChatHistorySearchQuery());
      expect(controller.loading, isTrue);
      expect(controller.hasSearched, isTrue);
      response.complete([]);
      await future;
      expect(controller.loading, isFalse);
      expect(controller.failed, isFalse);
      expect(controller.results, isEmpty);
      expect(controller.hasMore, isFalse);
      expect(source.calls.single.conversationID, 'chat');
      expect(source.calls.single.pageIndex, 1);
      expect(source.calls.single.count, 30);
    });

    test('sender search scans nonmatching first page before returning results',
        () async {
      final source = FakeSearchSource((call) async => switch (call.pageIndex) {
            1 => page('bob', sender: 'bob'),
            2 => page('alice'),
            _ => [message('alice-last')],
          });
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      await controller
          .search(const ChatHistorySearchQuery(senderIDs: ['alice']));
      expect(controller.results.length, 30);
      expect(controller.results.every((m) => m.sendID == 'alice'), isTrue);
      expect(source.calls.map((call) => call.pageIndex), [1, 2]);
      expect(controller.hasMore, isTrue);
      await controller.loadMore();
      expect(controller.results.length, 31);
      expect(source.calls.map((call) => call.pageIndex), [1, 2, 3]);
      expect(controller.hasMore, isFalse);
    });

    test('media filtering scans a full sticker page using raw pagination',
        () async {
      final stickers = List.generate(30, (index) {
        final sticker = message('sticker-$index')
          ..contentType = MessageType.video;
        markStickerVideoMessage(sticker);
        return sticker;
      });
      final video = message('ordinary-video')..contentType = MessageType.video;
      final source = FakeSearchSource((call) async => switch (call.pageIndex) {
            1 => stickers,
            2 => [video],
            _ => throw StateError('The last raw page already ended.'),
          });
      final controller = ChatHistorySearchController(
        conversationID: 'video-chat',
        source: source,
        acceptResult: (item) => !isStickerVideoMessage(item),
      );
      addTearDown(controller.dispose);

      await controller.search(
          const ChatHistorySearchQuery(messageTypes: [MessageType.video]));

      expect(controller.results, [video]);
      expect(controller.hasMore, isFalse);
      expect(controller.failed, isFalse);
      expect(source.calls.map((call) => call.pageIndex), [1, 2]);
      for (final call in source.calls) {
        expect(call.conversationID, 'video-chat');
        expect(call.count, ChatHistorySearchController.pageSize);
        expect(call.query, same(controller.query));
        expect(call.query.messageTypes, [MessageType.video]);
        expect(call.query.sdkMessageTypes, [MessageType.video]);
        expect(call.query.keyword, isEmpty);
        expect(call.query.senderIDs, isEmpty);
        expect(call.query.startDate, isNull);
        expect(call.query.endDate, isNull);
      }
      await controller.loadMore();
      expect(source.calls, hasLength(2));
    });

    test('default controller keeps sticker videos in ordinary search results',
        () async {
      final sticker = message('sticker')..contentType = MessageType.video;
      markStickerVideoMessage(sticker);
      final video = message('video')..contentType = MessageType.video;
      final source = FakeSearchSource((_) async => [sticker, video]);
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);

      await controller.search(
          const ChatHistorySearchQuery(messageTypes: [MessageType.video]));

      expect(controller.results, [sticker, video]);
      expect(controller.hasMore, isFalse);
      expect(source.calls.map((call) => call.pageIndex), [1]);
    });

    test('filtered overflow is carried forward without refetching native pages',
        () async {
      final source = FakeSearchSource((call) async => switch (call.pageIndex) {
            1 => [
                ...page('a', count: 20),
                ...page('b', count: 10, sender: 'bob'),
              ],
            2 => page('next'),
            _ => [],
          });
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      await controller
          .search(const ChatHistorySearchQuery(senderIDs: ['alice']));
      expect(controller.results.length, 30);
      await controller.loadMore();
      expect(controller.results.length, 50);
      expect(controller.results.map((m) => m.clientMsgID).toSet().length, 50);
      expect(source.calls.map((call) => call.pageIndex), [1, 2, 3]);
      expect(controller.hasMore, isFalse);
    });

    test('first-page failure retries the same request', () async {
      var attempts = 0;
      final source = FakeSearchSource((_) async {
        if (++attempts == 1) throw StateError('SDK unavailable');
        return [message('found')];
      });
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      await controller.search(const ChatHistorySearchQuery(keyword: 'needle'));
      expect(controller.failed, isTrue);
      expect(controller.loading, isFalse);
      await controller.retry();
      expect(controller.failed, isFalse);
      expect(controller.results.single.clientMsgID, 'found');
      expect(source.calls.map((call) => call.pageIndex), [1, 1]);
      expect(source.calls.last.query.keyword, 'needle');
    });

    test('pagination failure preserves loaded messages and retries its cursor',
        () async {
      var secondPageAttempts = 0;
      final source = FakeSearchSource((call) async {
        if (call.pageIndex == 1) return page('first');
        if (++secondPageAttempts == 1) throw StateError('offline');
        return [message('last')];
      });
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      await controller.search(const ChatHistorySearchQuery());
      await controller.loadMore();
      expect(controller.results.length, 30);
      expect(controller.failed, isTrue);
      await controller.retry();
      expect(source.calls.map((call) => call.pageIndex), [1, 2, 2]);
      expect(controller.results.length, 31);
      expect(controller.failed, isFalse);
    });

    test('overlapping native pages do not duplicate messages', () async {
      final source = FakeSearchSource((call) async => call.pageIndex == 1
          ? page('first')
          : [message('first-29'), message('last')]);
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      await controller.search(const ChatHistorySearchQuery());
      await controller.loadMore();
      expect(controller.results.length, 31);
      expect(controller.results.last.clientMsgID, 'last');
      expect(controller.hasMore, isFalse);
    });

    test('new search isolates old success, failure and subsequent scanning',
        () async {
      final old = Completer<List<Message>>();
      final current = Completer<List<Message>>();
      final source = FakeSearchSource(
          (call) => call.query.keyword == 'old' ? old.future : current.future);
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      final first =
          controller.search(const ChatHistorySearchQuery(keyword: 'old'));
      final second =
          controller.search(const ChatHistorySearchQuery(keyword: 'current'));
      old.complete(page('stale', sender: 'bob'));
      await first;
      expect(controller.loading, isTrue);
      expect(controller.results, isEmpty);
      current.complete([message('current')]);
      await second;
      expect(controller.results.single.clientMsgID, 'current');
      expect(controller.query.keyword, 'current');
      expect(source.calls.length, 2);
    });

    for (final fails in [false, true]) {
      test('clearing ignores a pending ${fails ? 'failure' : 'success'}',
          () async {
        final response = Completer<List<Message>>();
        final source = FakeSearchSource((_) => response.future);
        final controller =
            ChatHistorySearchController(conversationID: 'chat', source: source);
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);
        final pending =
            controller.search(const ChatHistorySearchQuery(keyword: 'old'));
        expect(controller.loading, isTrue);
        controller.clear();
        expect(controller.hasSearched, isFalse);
        expect(controller.hasMore, isFalse);
        expect(controller.loading, isFalse);
        expect(controller.failed, isFalse);
        expect(controller.results, isEmpty);
        final clearedNotifications = notifications;
        if (fails) {
          response.completeError(StateError('stale failure'));
        } else {
          response.complete(page('stale'));
        }
        await pending;
        await controller.retry();
        await controller.loadMore();
        expect(source.calls, hasLength(1));
        expect(controller.results, isEmpty);
        expect(controller.loading, isFalse);
        expect(controller.failed, isFalse);
        expect(controller.hasSearched, isFalse);
        expect(notifications, clearedNotifications,
            reason:
                'The cleared generation cannot notify or fetch more pages.');
      });
    }

    test('clearing loaded results resets paging before the next keyword',
        () async {
      final source = FakeSearchSource((call) async =>
          call.query.keyword == 'old' ? page('old') : [message('current')]);
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      await controller.search(const ChatHistorySearchQuery(keyword: 'old'));
      expect(controller.results, hasLength(30));
      expect(controller.hasMore, isTrue);
      controller.clear();
      expect(controller.results, isEmpty);
      expect(controller.hasMore, isFalse);
      await controller.loadMore();
      expect(source.calls, hasLength(1));
      await controller.search(const ChatHistorySearchQuery(keyword: 'current'));
      expect(controller.results.single.clientMsgID, 'current');
      expect(source.calls.last.query.keyword, 'current');
      expect(source.calls.last.pageIndex, 1);
      expect(controller.hasMore, isFalse);
    });

    test('repeated pagination taps do not dispatch duplicate requests',
        () async {
      final response = Completer<List<Message>>();
      final source = FakeSearchSource((call) async =>
          call.pageIndex == 1 ? page('first') : response.future);
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      addTearDown(controller.dispose);
      await controller.search(const ChatHistorySearchQuery());
      final loading = controller.loadMore();
      await controller.loadMore();
      expect(source.calls.length, 2);
      response.complete([]);
      await loading;
      await controller.loadMore();
      expect(source.calls.length, 2);
    });

    test('disposing a pending search suppresses changes and later SDK pages',
        () async {
      final response = Completer<List<Message>>();
      final source = FakeSearchSource((_) => response.future);
      final controller =
          ChatHistorySearchController(conversationID: 'chat', source: source);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final loading =
          controller.search(const ChatHistorySearchQuery(senderIDs: ['alice']));
      controller.dispose();
      response.complete(page('bob', sender: 'bob'));
      await loading;
      await controller.retry();
      await controller.loadMore();
      await controller.search(const ChatHistorySearchQuery());
      controller.clear();
      expect(notifications, 1);
      expect(source.calls.length, 1);
      expect(controller.results, isEmpty);
    });
  });

  group('real SDK adapter contract', () {
    const channel = MethodChannel('flutter_openim_sdk');
    setUp(() {
      OpenIM.iMManager.userID = 'self';
      OpenIM.iMManager.token = 'test-session-a';
    });
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('passes all filters and only returns the requested conversation',
        () async {
      late Map<dynamic, dynamic> filters;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'searchLocalMessages');
        filters = (call.arguments as Map)['filter'] as Map;
        return jsonEncode({
          'searchResultItems': [
            {
              'conversationID': 'chat',
              'messageList': [message('allowed').toJson()]
            },
            {
              'conversationID': 'other',
              'messageList': [message('outside').toJson()]
            },
          ],
        });
      });
      final query = ChatHistorySearchQuery(
        messageTypes: [MessageType.file],
        senderIDs: ['alice'],
        startDate: DateTime(2026, 10, 5),
        endDate: DateTime(2026, 10, 5),
      );
      final result = await OpenIMChatHistorySearchSource()
          .search(conversationID: 'chat', query: query, pageIndex: 2);
      expect(filters['conversationID'], 'chat');
      expect(filters['keywordList'], isEmpty);
      expect(filters['messageTypeList'], [MessageType.file]);
      expect(filters['senderUserIDList'], ['alice']);
      expect(filters['searchTimePosition'], query.searchTimePosition);
      expect(filters['searchTimePeriod'], query.searchTimePeriod);
      expect(filters['pageIndex'], 2);
      expect(filters['count'], 30);
      expect(result.single.clientMsgID, 'allowed');
    });

    test('does not silently turn an empty conversation into global search',
        () async {
      expect(
          OpenIMChatHistorySearchSource().search(
            conversationID: ' ',
            query: const ChatHistorySearchQuery(),
            pageIndex: 1,
          ),
          throwsArgumentError);
    });

    for (final changeUser in [true, false]) {
      test(
          'rejects pending SDK results after ${changeUser ? 'account' : 'session token'} change',
          () async {
        final response = Completer<String>();
        final started = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) {
          started.complete();
          return response.future;
        });
        final source = OpenIMChatHistorySearchSource();
        final pending = source.search(
            conversationID: 'chat',
            query: const ChatHistorySearchQuery(),
            pageIndex: 1);
        await started.future;
        if (changeUser) {
          OpenIM.iMManager.userID = 'other-account';
        } else {
          OpenIM.iMManager.token = 'test-session-b';
        }
        response.complete(jsonEncode({
          'searchResultItems': [
            {
              'conversationID': 'chat',
              'messageList': [message('old-account-data').toJson()],
            },
          ],
        }));
        await expectLater(pending, throwsStateError);
      });
    }

    test('rejects later raw pages after account change before calling SDK',
        () async {
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        requests++;
        return jsonEncode({'searchResultItems': []});
      });
      final source = OpenIMChatHistorySearchSource();
      await source.search(
          conversationID: 'chat',
          query: const ChatHistorySearchQuery(),
          pageIndex: 1);
      OpenIM.iMManager.userID = 'other-account';
      await expectLater(
          source.search(
              conversationID: 'chat',
              query: const ChatHistorySearchQuery(),
              pageIndex: 2),
          throwsStateError);
      expect(requests, 1);
    });
  });
}
