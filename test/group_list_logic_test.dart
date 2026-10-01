import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/group_list/group_list_logic.dart';

GroupInfo group(String id, {String owner = 'self'}) =>
    GroupInfo(groupID: id, ownerUserID: owner);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlapping refreshes keep only the latest response', () async {
    final requests = <Completer<List<GroupInfo>>>[];
    final logic = GroupListLogic(
        currentUserID: () => 'self',
        fetchPage: (_, __) {
          final request = Completer<List<GroupInfo>>();
          requests.add(request);
          return request.future;
        });
    final first = logic.iCreatedInitial();
    final second = logic.iCreatedInitial();
    requests[1].complete([group('one'), group('one')]);
    await second;
    requests[0].complete([group('old')]);
    await first;
    expect(logic.iCreatedList.map((g) => g.groupID), ['one']);
    logic.onClose();
  });

  test('pagination advances by raw count and merges overlapping group IDs',
      () async {
    final offsets = <int>[];
    final logic = GroupListLogic(
        currentUserID: () => 'self',
        fetchPage: (offset, _) async {
          offsets.add(offset);
          return offset == 0
              ? [group('one'), group('other', owner: 'other')]
              : [group('one')];
        })
      ..count = 2;
    await logic.iCreatedInitial();
    await logic.iCreatedLoadMore();
    await logic.iCreatedLoadMore();
    expect(offsets, [0, 2]);
    expect(logic.iCreatedList.length, 1);
    logic.onClose();
  });

  test('failed refresh preserves rows and can be retried', () async {
    var fail = false;
    final logic = GroupListLogic(
        currentUserID: () => 'self',
        fetchPage: (_, __) async {
          if (fail) throw StateError('offline');
          return [group('one', owner: 'other')];
        });
    await logic.iJoinedInitial();
    fail = true;
    await logic.iJoinedInitial();
    expect(logic.iJoinedList.length, 1);
    fail = false;
    await logic.iJoinedInitial();
    expect(logic.iJoinedList.length, 1);
    logic.onClose();
  });

  test('response after disposal does not update rows', () async {
    final response = Completer<List<GroupInfo>>();
    final logic = GroupListLogic(
        currentUserID: () => 'self', fetchPage: (_, __) => response.future);
    final pending = logic.iCreatedInitial();
    logic.onClose();
    response.complete([group('one')]);
    await pending;
    expect(logic.iCreatedList, isEmpty);
  });
}
