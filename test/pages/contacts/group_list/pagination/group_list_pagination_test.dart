import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/group_list/group_list_logic.dart';

GroupInfo group(String id, String name, {String owner = 'self'}) =>
    GroupInfo(groupID: id, groupName: name, ownerUserID: owner);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads all pages so alphabet navigation reaches the complete directory',
      () async {
    final offsets = <int>[];
    final logic = GroupListLogic(
        currentUserID: () => 'self',
        fetchPage: (offset, _) async {
          offsets.add(offset);
          return switch (offset) {
            0 => [
                group('other1', 'Adam', owner: 'peer'),
                group('other2', 'Bob', owner: 'peer')
              ],
            2 => [group('z', '寮犱笁'), group('a', 'Alice')],
            _ => [group('z', '寮犱笁鏇存柊')],
          };
        })
      ..count = 2;
    await logic.iCreatedInitial();
    expect(offsets, [0, 2, 4]);
    expect(logic.iCreatedList.map((group) => group.groupID), ['z', 'a']);
    expect(logic.canLoadMore(true), isFalse);
    expect(logic.isComplete(true), isTrue);
    await logic.iCreatedLoadMore();
    expect(offsets, [0, 2, 4]);
    expect(logic.iCreatedList.map((group) => group.groupID), ['z', 'a']);
    expect(logic.iCreatedList.first.groupName, '寮犱笁鏇存柊');
    expect(logic.iCreatedOffset, 5);
    expect(logic.canLoadMore(true), isFalse);
    expect(logic.isComplete(true), isTrue);
    logic.onClose();
  });

  test('failed next page retains rows and retries the same offset', () async {
    var fail = true;
    final offsets = <int>[];
    final logic = GroupListLogic(
        currentUserID: () => 'self',
        fetchPage: (offset, _) async {
          offsets.add(offset);
          if (offset == 0) return [group('old', '寮犱笁'), group('old2', 'Alice')];
          if (fail) throw StateError('offline');
          return [group('new', '鏂扮兢')];
        })
      ..count = 2;
    await logic.iCreatedInitial();
    expect(logic.loadFailed[true], isTrue);
    expect(logic.iCreatedList.map((group) => group.groupID), ['old', 'old2']);
    expect(logic.iCreatedOffset, 2);
    expect(logic.canLoadMore(true), isTrue);
    expect(logic.isComplete(true), isFalse);
    fail = false;
    await logic.iCreatedLoadMore();
    expect(logic.loadFailed[true], isFalse);
    expect(offsets, [0, 2, 2]);
    expect(logic.iCreatedList.map((group) => group.groupID),
        ['old', 'old2', 'new']);
    expect(logic.isComplete(true), isTrue);
    logic.onClose();
  });

  test('account change cancels remaining pages without publishing rows',
      () async {
    var account = 'self';
    final page = Completer<List<GroupInfo>>();
    final logic = GroupListLogic(
        currentUserID: () => account, fetchPage: (_, __) => page.future)
      ..count = 1;
    final pending = logic.iCreatedInitial();
    account = 'other';
    page.complete([group('private', 'Alice')]);
    await pending;
    expect(logic.iCreatedList, isEmpty);
    logic.onClose();
  });
}
