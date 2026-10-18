import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_controller.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/cloud/chat_keyword_search_api.dart';

class NoLocalSearch extends ChatHistorySearchSource {
  int calls = 0;
  @override
  Future<List<Message>> search(
      {required String conversationID,
      required ChatHistorySearchQuery query,
      required int pageIndex,
      int count = 30}) async {
    calls++;
    throw StateError('Date/member search must use the server');
  }
}

void main() {
  for (final byDate in [false, true]) {
    test('cloud filter skips empty pages and keeps snapshot, date=$byDate',
        () async {
      final local = NoLocalSearch();
      final day = DateTime(2026, 10, 1);
      final requests = <Map<String, dynamic>>[];
      final api = ChatKeywordSearchApi(
        session: () =>
            (user: 'self', token: 'token', server: 'https://im.test'),
        post: (url, body, _) async {
          expect(url, 'https://im.test/msg/search_history_filters');
          requests.add(body);
          final first = requests.length == 1;
          return {
            'errCode': 0,
            'data': {
              'snapshotSeq': 500,
              'nextBeforeSeq': first ? 301 : 0,
              'hasMore': first,
              'items': first
                  ? []
                  : [
                      {
                        'conversationID': 'sg_test',
                        'clientMsgID': 'old-photo',
                        'seq': 250,
                        'sendID': 'member',
                        'sendTime': day.millisecondsSinceEpoch + 1000,
                        'contentType': 102,
                        'summary': '[图片]',
                      }
                    ],
            }
          };
        },
      );
      final controller = ChatHistorySearchController(
          conversationID: 'sg_test', source: local, keywordApi: api);
      await controller.search(byDate
          ? ChatHistorySearchQuery(startDate: day, endDate: day)
          : const ChatHistorySearchQuery(senderIDs: ['member']));
      expect(controller.failed, isFalse);
      expect(controller.invalidKeyword, isFalse);
      expect(controller.results.single.clientMsgID, 'old-photo');
      expect(controller.hasMore, isFalse);
      expect(local.calls, 0);
      expect(requests[1]['snapshotSeq'], 500);
      expect(requests[1]['beforeSeq'], 301);
      expect(requests[0]['senderIDs'], byDate ? [] : ['member']);
      expect(requests[0]['startTime'], byDate ? day.millisecondsSinceEpoch : 0);
      controller.dispose();
    });
  }
  test('filter network failure is retryable and never becomes local no-data',
      () async {
    final local = NoLocalSearch();
    var fail = true;
    final api = ChatKeywordSearchApi(
      session: () => (user: 'self', token: 'token', server: 'https://im.test'),
      post: (_, __, ___) async => fail
          ? {'errCode': 503}
          : {
              'errCode': 0,
              'data': {
                'items': [],
                'hasMore': false,
                'snapshotSeq': 50,
                'nextBeforeSeq': 0
              }
            },
    );
    final controller = ChatHistorySearchController(
        conversationID: 'sg_test', source: local, keywordApi: api);
    await controller
        .search(const ChatHistorySearchQuery(senderIDs: ['member']));
    expect(controller.failed, isTrue);
    fail = false;
    await controller.retry();
    expect(controller.failed, isFalse);
    expect(controller.hasMore, isFalse);
    expect(local.calls, 0);
    controller.dispose();
  });
}
