import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/cloud/chat_keyword_search_api.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_controller.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';

const session =
    (user: 'self', token: 'user-im-token', server: 'https://im.example');
Map<String, dynamic> result(int seq) => {
      'conversationID': 'sg_test',
      'clientMsgID': 'm$seq',
      'serverMsgID': 's$seq',
      'seq': seq,
      'sendID': 'sender',
      'sendTime': 1234567890123,
      'contentType': 101,
      'summary': '<b>会议</b>',
    };
Map<String, dynamic> page(List<Map<String, dynamic>> items,
        {bool more = false, int before = 0, int snapshot = 100}) =>
    {
      'errCode': 0,
      'data': {
        'items': items,
        'hasMore': more,
        'nextBeforeSeq': before,
        'snapshotSeq': snapshot
      },
    };

void main() {
  test('uses imToken and exact milliseconds without identity in request body',
      () async {
    final api = ChatKeywordSearchApi(
        session: () => session,
        post: (url, body, options) async {
          expect(url, 'https://im.example/msg/search_messages');
          expect(options.headers!['token'], 'user-im-token');
          expect(options.headers!['operationID'], isNotEmpty);
          expect(body.containsKey('userID'), isFalse);
          expect(body.containsKey('ownerUserID'), isFalse);
          expect(body['keyword'], '会议');
          expect(body['startTime'], 1234567890123);
          expect(body['endTime'], 1234567890999);
          expect(body['contentTypes'], [101, 106, 114, 117]);
          return page([result(99)]);
        });
    final response = await api.search(
        conversationID: 'sg_test',
        keyword: '会议',
        startTime: 1234567890123,
        endTime: 1234567890999);
    expect(response.items.single.summary, '<b>会议</b>');
  });
  test('Unicode character validation prevents invalid network requests',
      () async {
    var calls = 0;
    final api = ChatKeywordSearchApi(
        session: () => session,
        post: (_, __, ___) async {
          calls++;
          return page([]);
        });
    for (final keyword in ['中', '😀', '中' * 65]) {
      await expectLater(api.search(conversationID: 'sg_test', keyword: keyword),
          throwsFormatException);
    }
    expect(calls, 0);
    await api.search(conversationID: 'sg_test', keyword: '😀中');
    expect(calls, 1);
  });
  test('controller follows empty pages, preserves snapshot and stops at end',
      () async {
    final requests = <Map<String, dynamic>>[];
    final responses = [
      page([], more: true, before: 90),
      page([result(80)], more: true, before: 80),
      page([result(70)])
    ];
    final api = ChatKeywordSearchApi(
        session: () => session,
        post: (_, body, __) async {
          requests.add(body);
          return responses.removeAt(0);
        });
    final controller =
        ChatHistorySearchController(conversationID: 'sg_test', keywordApi: api);
    await controller.search(const ChatHistorySearchQuery(keyword: '会议'));
    expect(controller.results.single.seq, 80);
    expect(requests[1]['beforeSeq'], 90);
    expect(requests[1]['snapshotSeq'], 100);
    await controller.loadMore();
    expect(requests[2]['beforeSeq'], 80);
    expect(requests[2]['snapshotSeq'], 100);
    expect(controller.results.map((m) => m.seq), [80, 70]);
    expect(controller.hasMore, isFalse);
    await controller.loadMore();
    expect(requests, hasLength(3));
    controller.dispose();
  });
  test(
      'server failure preserves results and retry cursor without local fallback',
      () async {
    final requests = <Map<String, dynamic>>[];
    var fail = false;
    final api = ChatKeywordSearchApi(
        session: () => session,
        post: (_, body, __) async {
          requests.add(body);
          if (fail) return {'errCode': 503, 'errMsg': 'index unavailable'};
          return body['beforeSeq'] == 0
              ? page([result(80)], more: true, before: 80)
              : page([]);
        });
    final controller =
        ChatHistorySearchController(conversationID: 'sg_test', keywordApi: api);
    await controller.search(const ChatHistorySearchQuery(keyword: '会议'));
    fail = true;
    await controller.loadMore();
    expect(controller.failed, isTrue);
    expect(controller.results, hasLength(1));
    fail = false;
    await controller.retry();
    expect(requests[1], requests[2]);
    expect(controller.hasMore, isFalse);
    controller.dispose();
  });
  test('rejects wrong conversation and nonadvancing cursors', () async {
    for (final response in [
      page([
        {...result(80), 'conversationID': 'other'}
      ]),
      page([], more: true, before: 90)
    ]) {
      final api = ChatKeywordSearchApi(
          session: () => session, post: (_, __, ___) async => response);
      await expectLater(
          api.search(
              conversationID: 'sg_test',
              keyword: '会议',
              beforeSeq: 90,
              snapshotSeq: 100),
          throwsFormatException);
    }
  });
  test('cleared query ignores late results and session change rejects response',
      () async {
    final pending = Completer<dynamic>();
    var activeSession = session;
    final api = ChatKeywordSearchApi(
        session: () => activeSession, post: (_, __, ___) => pending.future);
    final controller =
        ChatHistorySearchController(conversationID: 'sg_test', keywordApi: api);
    final work = controller.search(const ChatHistorySearchQuery(keyword: '会议'));
    controller.clear();
    activeSession =
        (user: 'other', token: 'other-token', server: session.server);
    pending.complete(page([result(80)]));
    await work;
    expect(controller.results, isEmpty);
    expect(controller.failed, isFalse);
    await expectLater(api.search(conversationID: 'sg_test', keyword: '会议'),
        throwsA(isA<SearchApiException>()));
    controller.dispose();
  });
}
