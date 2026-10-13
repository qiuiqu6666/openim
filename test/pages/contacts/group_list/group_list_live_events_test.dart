import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/pages/contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/chat_closure/chat_closure_fixture.dart';

class _Directory extends GroupListLogic {
  _Directory({required super.fetchPage});
  @override
  GroupFeatureStore? get groupFeatures => null;
}

GroupInfo group(String id, {String owner = 'self', String? name}) =>
    GroupInfo(groupID: id, groupName: name ?? id, ownerUserID: owner);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ClosureIM im;
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'self';
    Get.put<AppController>(ClosureApp());
    im = Get.put<IMController>(ClosureIM()) as ClosureIM;
  });
  tearDown(Get.reset);

  test(
      'rename, ownership transfer, join and leave update both tabs immediately',
      () async {
    var calls = 0;
    final logic = _Directory(fetchPage: (_, __) async {
      calls++;
      return [group('owned'), group('joined', owner: 'peer')];
    })
      ..onInit();
    addTearDown(() => logic.onDelete());
    await Future<void>.delayed(Duration.zero);
    expect(logic.iCreatedList.single.groupID, 'owned');
    im.groupInfoUpdatedSubject
        .add(group('owned', owner: 'peer', name: 'Renamed'));
    im.joinedGroupAddedSubject.add(group('new'));
    im.joinedGroupDeletedSubject.add(group('joined', owner: 'peer'));
    await Future<void>.delayed(Duration.zero);
    expect(logic.iCreatedList.map((g) => g.groupID), ['new']);
    expect(logic.iJoinedList.single.groupName, 'Renamed');
    expect(calls, 2, reason: 'One event burst cannot start a query per event.');
  });

  test('pushes and self removal beat old pending directory pages', () async {
    final pages = <Completer<List<GroupInfo>>>[];
    final logic = _Directory(fetchPage: (_, __) {
      final page = Completer<List<GroupInfo>>();
      pages.add(page);
      return page.future;
    })
      ..onInit();
    addTearDown(() => logic.onDelete());
    expect(pages, hasLength(2));
    im.groupInfoUpdatedSubject.add(group('owned', name: 'Renamed'));
    im.memberDeletedSubject
        .add(GroupMembersInfo(groupID: 'joined', userID: 'self'));
    await Future<void>.delayed(Duration.zero);
    for (final page in pages) {
      page.complete([group('owned'), group('joined', owner: 'peer')]);
    }
    await Future<void>.delayed(Duration.zero);
    expect(logic.iCreatedList.single.groupName, 'Renamed');
    expect(logic.iJoinedList, isEmpty);
    im.groupInfoUpdatedSubject.add(group('joined', owner: 'peer'));
    await Future<void>.delayed(Duration.zero);
    expect(logic.iJoinedList, isEmpty,
        reason: 'A late metadata push cannot undo leaving.');
  });

  test('ownership transfer during initial reads classifies the newer owner',
      () async {
    final pages = <Completer<List<GroupInfo>>>[];
    final logic = _Directory(fetchPage: (_, __) {
      final reply = Completer<List<GroupInfo>>();
      pages.add(reply);
      return reply.future;
    })
      ..onInit();
    addTearDown(() => logic.onDelete());
    im.groupInfoUpdatedSubject.add(group('transferred', owner: 'peer'));
    await Future<void>.delayed(Duration.zero);
    for (final page in pages) {
      page.complete([group('transferred')]);
    }
    await Future<void>.delayed(Duration.zero);
    expect(logic.iCreatedList, isEmpty);
    expect(logic.iJoinedList.single.groupID, 'transferred');
  });

  test('a changed account cannot receive live directory events', () async {
    final logic = _Directory(fetchPage: (_, __) async => [group('owned')])
      ..onInit();
    addTearDown(() => logic.onDelete());
    await Future<void>.delayed(Duration.zero);
    OpenIM.iMManager.userID = 'other';
    im.joinedGroupAddedSubject.add(group('private', owner: 'other'));
    im.joinedGroupDeletedSubject.add(group('owned'));
    await Future<void>.delayed(Duration.zero);
    expect(logic.iCreatedList.map((g) => g.groupID), ['owned']);
  });
}
