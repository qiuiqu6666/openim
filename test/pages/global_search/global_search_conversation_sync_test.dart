import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';

class _UpdatingSource extends GlobalSearchSource {
  final updates =
      StreamController<List<ConversationInfo>>.broadcast(sync: true);
  final pending = <String, Completer<List<ConversationInfo>>>{};
  List<ConversationInfo> initial = [];
  bool delayedConversations = false;
  final calls = <String, int>{};

  void _count(String section) =>
      calls.update(section, (count) => count + 1, ifAbsent: () => 1);

  @override
  Stream<List<ConversationInfo>> get conversationUpdates => updates.stream;

  @override
  Future<List<FriendInfo>> friends(String query) async {
    _count('contacts');
    return [];
  }

  @override
  Future<List<GroupInfo>> groups(String query) async {
    _count('groups');
    return [];
  }

  @override
  Future<List<ConversationInfo>> conversations(String query) {
    _count('conversations');
    return delayedConversations
        ? (pending[query] = Completer<List<ConversationInfo>>()).future
        : Future.value(initial);
  }

  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async {
    _count(files ? 'files' : 'messages');
    return [];
  }
}

ConversationInfo _item(String name,
        {String? draft, String? user, String? group}) =>
    ConversationInfo(
      conversationID: name,
      showName: name,
      userID: user,
      groupID: group,
      draftText: draft,
      unreadCount: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _UpdatingSource source;
  late GlobalSearchLogic logic;

  setUp(() {
    Get.testMode = true;
    source = _UpdatingSource();
    logic = Get.put(GlobalSearchLogic(source: source));
  });

  tearDown(() async {
    Get.reset();
    await source.updates.close();
  });

  test(
      'updated conversation draft replaces search result without remote searches',
      () async {
    source.initial = [_item('冬', draft: '旧草稿')];
    logic.searchCtrl.text = '冬';
    await logic.search();
    expect(logic.conversations.single.draftText, '旧草稿');

    source.updates.add([
      _item('冬', draft: '刚从聊天返回保存的新草稿'),
      _item('夏', draft: '其他会话草稿'),
    ]);
    expect(logic.conversations.single.draftText, '刚从聊天返回保存的新草稿');
    expect(source.calls, {
      'contacts': 1,
      'groups': 1,
      'conversations': 1,
      'messages': 1,
      'files': 1,
    });
    source.updates.add([_item('冬', draft: '')]);
    expect(logic.conversations.single.draftText, '');
    expect(source.calls.values.every((count) => count == 1), isTrue);
  });

  test('SDK list updates filter by current name and identifiers ignoring case',
      () async {
    logic.searchCtrl.text = '  MEMBER  ';
    await logic.search();
    source.updates.add([
      _item('member 昵称'),
      _item('好友', user: 'member-123'),
      _item('群聊', group: 'MEMBER-group'),
      _item('无匹配', user: 'other-user', group: 'other-group'),
    ]);
    expect(logic.conversations.map((item) => item.showName),
        ['member 昵称', '好友', '群聊']);
  });

  test('late search snapshot cannot overwrite a newer conversation draft',
      () async {
    source.delayedConversations = true;
    logic.searchCtrl.text = '冬';
    final search = logic.search();
    source.updates.add([_item('冬', draft: '新草稿')]);
    source.pending['冬']!.complete([_item('冬', draft: '搜索开始时的旧草稿')]);
    await search;
    expect(logic.conversations.single.draftText, '新草稿');
    expect(logic.loading.value, isFalse);
  });

  test('old queries and cleared searches do not repopulate stale conversations',
      () async {
    source.delayedConversations = true;
    logic.searchCtrl.text = '冬';
    final oldSearch = logic.search();
    logic.searchCtrl.text = '夏';
    final newSearch = logic.search();
    source.updates.add([_item('冬'), _item('夏', draft: '当前夏草稿')]);
    source.pending['冬']!.complete([_item('冬', draft: '过时查询')]);
    source.pending['夏']!.complete([_item('夏', draft: '过时快照')]);
    await Future.wait([oldSearch, newSearch]);
    expect(logic.conversations.single.showName, '夏');
    expect(logic.conversations.single.draftText, '当前夏草稿');

    logic.searchCtrl.clear();
    source.updates.add([_item('夏', draft: '清空搜索后的变更')]);
    expect(logic.conversations, isEmpty);
    expect(logic.query.value, isEmpty);
    expect(logic.loading.value, isFalse);
  });

  test('closing search cancels local updates and ignores pending snapshots',
      () async {
    source.delayedConversations = true;
    logic.searchCtrl.text = '冬';
    final search = logic.search();
    expect(source.updates.hasListener, isTrue);
    await Get.delete<GlobalSearchLogic>();
    expect(source.updates.hasListener, isFalse);
    source.updates.add([_item('冬', draft: '关闭之后')]);
    source.pending['冬']!.complete([_item('冬', draft: '关闭之后的旧查询')]);
    await search;
    expect(logic.conversations, isEmpty);
  });
}
