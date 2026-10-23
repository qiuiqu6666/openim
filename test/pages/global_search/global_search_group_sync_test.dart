import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';

class _Source extends GlobalSearchSource {
  final updates = StreamController<GroupInfo>.broadcast(sync: true);
  final removals = StreamController<GroupInfo>.broadcast(sync: true);
  final joins = StreamController<GroupInfo>.broadcast(sync: true);
  List<GroupInfo> rows = [
    GroupInfo(groupID: 'g1', groupName: 'old', faceURL: 'before')
  ];
  Completer<List<GroupInfo>>? pending;
  @override
  Stream<GroupInfo> get groupUpdates => updates.stream;
  @override
  Stream<GroupInfo> get groupRemovals => removals.stream;
  @override
  Stream<GroupInfo> get groupJoins => joins.stream;
  @override
  Iterable<ConversationInfo> get currentConversations => [
        ConversationInfo(
            conversationID: 'sg_g1',
            groupID: 'g1',
            conversationType: ConversationType.superGroup,
            showName: 'old',
            faceURL: 'before')
      ];
  @override
  Future<List<GroupInfo>> groups(String query) async {
    final delayed = pending;
    pending = null;
    return delayed == null ? rows : await delayed.future;
  }

  @override
  Future<List<FriendInfo>> friends(String query) async => [];
  @override
  Future<List<ConversationInfo>> conversations(String query) async =>
      currentConversations.toList();
  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Source source;
  late GlobalSearchLogic logic;
  setUp(() {
    Get.testMode = true;
    source = _Source();
    logic = Get.put(GlobalSearchLogic(source: source));
  });
  tearDown(() async {
    Get.reset();
    await source.updates.close();
    await source.removals.close();
    await source.joins.close();
  });
  Future<void> search(String query) async {
    logic.searchCtrl.text = query;
    await logic.search();
  }

  test(
      'UID results and conversation identities receive name and avatar updates',
      () async {
    await search('g1');
    source.updates
        .add(GroupInfo(groupID: 'g1', groupName: 'new', faceURL: 'after'));
    expect(logic.groupList.single.groupName, 'new');
    expect(logic.groupList.single.faceURL, 'after');
    final conversation =
        logic.currentConversation(source.currentConversations.single);
    expect(conversation.showName, 'new');
    expect(conversation.faceURL, 'after');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // The subsequent SDK snapshot is deliberately stale.
    expect(logic.groupList.single.groupName, 'new');
  });
  test('rename removes old keyword matches and adds new keyword matches',
      () async {
    await search('old');
    source.updates.add(GroupInfo(groupID: 'g1', groupName: 'new'));
    expect(logic.groupList, isEmpty);
    await search('new');
    expect(logic.groupList.single.groupName, 'new');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(logic.groupList.single.groupName, 'new');
  });
  test('a response started before an update cannot overwrite refreshed results',
      () async {
    final pending = source.pending = Completer<List<GroupInfo>>();
    logic.searchCtrl.text = 'g1';
    final running = logic.search();
    source.updates.add(GroupInfo(groupID: 'g1', groupName: 'new'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(logic.groupList.single.groupName, 'new');
    pending.complete([]);
    await running;
    expect(logic.groupList.single.groupName, 'new');
  });
  test('left groups stay removed through stale snapshots and may rejoin',
      () async {
    await search('g1');
    source.removals.add(GroupInfo(groupID: 'g1'));
    source.updates.add(GroupInfo(groupID: 'g1', groupName: 'stale'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(logic.groupList, isEmpty);
    source.joins.add(GroupInfo(groupID: 'g1', groupName: 'rejoined'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(logic.groupList.single.groupName, 'rejoined');
  });
  test('closing cancels listeners and late group refresh publication',
      () async {
    await search('g1');
    final pending = source.pending = Completer<List<GroupInfo>>();
    source.updates.add(GroupInfo(groupID: 'g1', groupName: 'new'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final revision = logic.groupRevision.value;
    logic.onClose();
    source.updates.add(GroupInfo(groupID: 'g1', groupName: 'ignored'));
    pending.complete([]);
    await Future<void>.delayed(Duration.zero);
    expect(logic.groupRevision.value, revision);
    expect(logic.groupList.single.groupName, 'new');
  });
}
