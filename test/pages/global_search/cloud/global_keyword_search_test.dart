import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/cloud/chat_keyword_search_api.dart';
import 'package:openim/pages/global_search/cloud/global_keyword_search_api.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';

class LocalSource extends GlobalSearchSource {
  int messageCalls = 0;
  @override
  Future<List<FriendInfo>> friends(String q) async => [];
  @override
  Future<List<GroupInfo>> groups(String q) async => [];
  @override
  Future<List<ConversationInfo>> conversations(String q) async => [];
  @override
  Future<List<SearchResultItems>> messages(String q, bool files) async {
    messageCalls++;
    return [];
  }
}

Map<String, dynamic> item(String conv, int seq) => {
      'conversationID': conv,
      'seq': seq,
      'clientMsgID': '$conv-$seq',
      'serverMsgID': 's$seq',
      'sendID': 'sender',
      'sendTime': 1000,
      'contentType': 101,
      'summary': '会议'
    };
Map<String, dynamic> response(List<Map<String, dynamic>> items,
        {bool more = false, String cursor = ''}) =>
    {
      'errCode': 0,
      'data': {
        'items': items,
        'hasMore': more,
        'nextCursor': cursor,
        'snapshotTime': 1000
      }
    };
GlobalKeywordSearchApi api(
        Future<dynamic> Function(Map<String, dynamic>) post) =>
    GlobalKeywordSearchApi(
        client: SearchHttpClient(
            session: () =>
                (user: 'self', token: 'im-token', server: 'https://im.example'),
            post: (url, body, options) {
              expect(url, 'https://im.example/msg/search_messages_global');
              expect(options.headers!['token'], 'im-token');
              expect(body['groupByConversation'], isTrue);
              expect(
                  body.keys,
                  unorderedEquals([
                    'keyword',
                    'groupByConversation',
                    'cursor',
                    'limit',
                    'startTime',
                    'endTime',
                    'contentTypes'
                  ]));
              return post(body);
            }));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'global HTTP replaces local scan, follows empty pages and deduplicates by conversation+seq',
      () async {
    final source = LocalSource();
    final requests = <Map<String, dynamic>>[];
    final results = [
      response([], more: true, cursor: 'one'),
      response([item('sg_a', 5), item('si_b', 5)], more: true, cursor: 'two'),
      response([item('sg_a', 5), item('sg_a', 4)])
    ];
    final logic = GlobalSearchLogic(
        source: source,
        keywordApi: api((body) async {
          requests.add(body);
          return results.removeAt(0);
        }));
    logic.searchCtrl.text = '会议';
    await logic.search();
    expect(logic.cloudHits.length, 2);
    expect(requests[1]['cursor'], 'one');
    await logic.loadMoreCloud();
    expect(logic.cloudHits.length, 3);
    expect(logic.cloudConversationHits.map((hit) => hit.conversationID),
        ['sg_a', 'si_b']);
    expect(logic.cloudConversationHits.first.seq, 5);
    expect(requests[2]['cursor'], 'two');
    expect(logic.cloudHasMore.value, isFalse);
    expect(source.messageCalls, 0);
    logic.onClose();
  });
  test('expired cursor resets search; 429 keeps results and retry cursor',
      () async {
    var code = 0;
    final cursors = <String>[];
    final logic = GlobalSearchLogic(
        source: LocalSource(),
        keywordApi: api((body) async {
          cursors.add(body['cursor'] as String);
          return code == 0
              ? response([item('sg_a', 5)], more: true, cursor: 'next')
              : {'errCode': code};
        }));
    logic.searchCtrl.text = '会议';
    await logic.search();
    code = 429;
    await logic.loadMoreCloud();
    expect(logic.cloudHits.length, 1);
    expect(logic.searchError.value, 429);
    code = 1001;
    await logic.loadMoreCloud();
    expect(logic.cloudHits, isEmpty);
    code = 0;
    await logic.loadMoreCloud();
    expect(cursors.last, '');
    logic.onClose();
  });
  test('new query cancels old work and late response cannot replace results',
      () async {
    final old = Completer<dynamic>();
    final started = Completer<void>();
    final logic = GlobalSearchLogic(
      source: LocalSource(),
      keywordApi: api((body) {
        if (body['keyword'] == '旧词') {
          started.complete();
          return old.future;
        }
        return Future.value(response([item('new', 2)]));
      }),
    )..onInit();
    logic.searchCtrl.text = '旧词';
    final first = logic.search();
    await started.future;
    logic.searchCtrl.text = '新词';
    await logic.search();
    await first.timeout(const Duration(seconds: 1));
    expect(old.isCompleted, isFalse);
    expect(logic.cloudHits.single.conversationID, 'new');
    expect(logic.pendingSections, isEmpty);
    expect(logic.failures, isEmpty);
    old.complete(response([item('old', 1)]));
    await Future<void>.delayed(Duration.zero);
    expect(logic.cloudHits.single.conversationID, 'new');
    logic.onClose();
  });

  test('closing page cancels pending cloud work without publishing an error',
      () async {
    final old = Completer<dynamic>();
    final started = Completer<void>();
    final logic = GlobalSearchLogic(
        source: LocalSource(),
        keywordApi: api((_) {
          started.complete();
          return old.future;
        }));
    logic.searchCtrl.text = '会议';
    final search = logic.search();
    await started.future;
    logic.onClose();
    await search.timeout(const Duration(seconds: 1));
    expect(logic.failures, isEmpty);
    old.complete(response([]));
  });

  test('clearing query invalidates pending global response', () async {
    final pending = Completer<dynamic>();
    final logic = GlobalSearchLogic(
        source: LocalSource(), keywordApi: api((_) => pending.future));
    logic.searchCtrl.text = '会议';
    final work = logic.search();
    logic.searchCtrl.clear();
    await logic.search();
    pending.complete(response([item('sg_a', 5)]));
    await work;
    expect(logic.cloudHits, isEmpty);
    expect(logic.cloudLoading.value, isFalse);
    logic.onClose();
  });
}
