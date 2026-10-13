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
              expect(
                  body.keys,
                  unorderedEquals([
                    'keyword',
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
