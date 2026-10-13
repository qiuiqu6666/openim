import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/global_search/cloud/global_history_cloud_search.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';

Message message(String id) =>
    Message(clientMsgID: id, contentType: MessageType.text);

class Source extends GlobalSearchSource {
  int searches = 0;
  bool hydrated = false;
  @override
  Stream<List<ConversationInfo>>? get conversationUpdates => null;
  @override
  Future<List<FriendInfo>> friends(String query) async => [];
  @override
  Future<List<GroupInfo>> groups(String query) async => [];
  @override
  Future<List<ConversationInfo>> conversations(String query) async => [];
  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async {
    searches++;
    return [
      if (hydrated)
        SearchResultItems(
            conversationID: 'group', messageList: [message(query)])
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'session';
  });
  test('global query replaces local results after cloud hydration', () async {
    final source = Source();
    final logic = GlobalSearchLogic(
        source: source,
        cloudFactory: () => GlobalHistoryCloudSearch(
            conversations: (_) async =>
                [ConversationInfo(conversationID: 'group')],
            history: (_, __, ___) async {
              source.hydrated = true;
              return AdvancedMessage(messageList: [], isEnd: true, errCode: 0);
            }));
    logic.searchCtrl.text = 'needle';
    await logic.search();
    expect(source.searches, 2);
    expect(logic.textSearchResultItems.single.messageList!.single.clientMsgID,
        'needle');
    expect(logic.cloudHasMore.value, isFalse);
    expect(logic.cloudLoading.value, isFalse);
    logic.onClose();
  });
  test('query change ignores late cloud result', () async {
    final pending = Completer<AdvancedMessage>();
    final started = Completer<void>();
    final source = Source();
    final logic = GlobalSearchLogic(
        source: source,
        cloudFactory: () => GlobalHistoryCloudSearch(
            conversations: (_) async =>
                [ConversationInfo(conversationID: 'group')],
            history: (_, __, ___) {
              started.complete();
              return pending.future;
            }));
    logic.searchCtrl.text = 'old';
    final work = logic.search();
    await started.future;
    logic.searchCtrl.clear();
    await logic.search();
    pending.complete(AdvancedMessage(messageList: [], isEnd: true, errCode: 0));
    await work;
    expect(logic.textSearchResultItems, isEmpty);
    expect(source.searches, 1);
    logic.onClose();
  });
  test(
      'load more finishes history even when an intermediate batch adds matches',
      () async {
    var pages = 0;
    final source = Source();
    final logic = GlobalSearchLogic(
        source: source,
        cloudFactory: () => GlobalHistoryCloudSearch(
            conversations: (_) async =>
                [ConversationInfo(conversationID: 'group')],
            history: (_, __, ___) async {
              pages++;
              if (pages == 2) source.hydrated = true;
              return AdvancedMessage(
                  messageList: [message('$pages')],
                  isEnd: pages == 4,
                  errCode: 0);
            }));
    logic.searchCtrl.text = 'missing';
    await logic.search();
    expect(pages, 1);
    await logic.loadMoreCloud();
    expect(pages, 4);
    expect(logic.cloudHasMore.value, isFalse);
    await logic.loadMoreCloud();
    expect(pages, 4);
    logic.onClose();
  });
}
