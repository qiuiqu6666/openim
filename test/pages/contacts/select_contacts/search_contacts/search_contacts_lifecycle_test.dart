import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/search_contacts/search_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/selection/contact_selection_policy.dart';
import 'package:openim_common/openim_common.dart';

class _Selection extends GetxController implements SelectContactsLogic {
  _Selection({this.action = SelAction.forward});
  @override
  final SelAction action;
  @override
  bool get hiddenGroup => action == SelAction.addMember;
  @override
  final defaultCheckedIDList = <String>{}.obs;
  @override
  bool isVisible(Object? info) => ContactSelectionPolicy.allowsVisible(info,
      showNotificationAccounts: action == SelAction.forward);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Search extends SelectContactsFromSearchLogic {
  final friends = <Completer<List<FriendInfo>>>[];
  final groups = <Completer<List<GroupInfo>>>[];
  final members = <Completer<List<GroupMembersInfo>>>[];
  @override
  Future<List<FriendInfo>> searchFriend() {
    final reply = Completer<List<FriendInfo>>();
    friends.add(reply);
    return reply.future;
  }

  @override
  Future<List<GroupInfo>> searchGroup() {
    final reply = Completer<List<GroupInfo>>();
    groups.add(reply);
    return reply.future;
  }

  @override
  Future<List<GroupMembersInfo>> getMemberInfo(List<String> uidList) {
    final reply = Completer<List<GroupMembersInfo>>();
    members.add(reply);
    return reply.future;
  }
}

Widget _overlay() => MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(initialEntries: [
          OverlayEntry(builder: (_) => GetMaterialApp(home: const Scaffold()))
        ]),
      ),
    );

void main() {
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
  });
  tearDown(() {
    LoadingView.singleton.dismiss();
    Get.reset();
  });

  testWidgets('forward search includes both friend and group SDK results',
      (tester) async {
    Get.put<SelectContactsLogic>(_Selection());
    await tester.pumpWidget(_overlay());
    final logic = _Search()..onInit();
    logic.searchCtrl.text = 'match';
    final search = logic.search();
    await tester.pump(const Duration(milliseconds: 2));
    logic.friends.single.complete([FriendInfo(userID: 'friend')]);
    logic.groups.single.complete([GroupInfo(groupID: 'group')]);
    await search;
    expect(logic.resultList.whereType<FriendInfo>().single.userID, 'friend');
    expect(logic.resultList.whereType<GroupInfo>().single.groupID, 'group');
    logic.onClose();
  });

  testWidgets('older friend and group results cannot replace a newer search',
      (tester) async {
    Get.put<SelectContactsLogic>(_Selection());
    await tester.pumpWidget(_overlay());
    final logic = _Search()..onInit();
    logic.searchCtrl.text = 'old';
    final old = logic.search();
    await tester.pump(const Duration(milliseconds: 2));
    logic.searchCtrl.text = 'new';
    final current = logic.search();
    await tester.pump(const Duration(milliseconds: 2));
    logic.friends[1].complete([FriendInfo(userID: 'new-friend')]);
    logic.groups[1].complete([GroupInfo(groupID: 'new-group')]);
    await current;
    logic.friends[0].complete([FriendInfo(userID: 'old-friend')]);
    logic.groups[0].complete([GroupInfo(groupID: 'old-group')]);
    await old;
    expect(
        logic.resultList.whereType<FriendInfo>().single.userID, 'new-friend');
    expect(logic.resultList.whereType<GroupInfo>().single.groupID, 'new-group');
    logic.onClose();
  });

  for (final action in [SelAction.forward, SelAction.recommend]) {
    testWidgets(
        '${action.name} search keeps notification visibility separate from selection',
        (tester) async {
      Get.put<SelectContactsLogic>(_Selection(action: action));
      await tester.pumpWidget(_overlay());
      final logic = _Search()..onInit();
      logic.searchCtrl.text = '99';
      final search = logic.search();
      await tester.pump(const Duration(milliseconds: 2));
      logic.friends.single.complete([
        FriendInfo(userID: '99Message'),
        FriendInfo(
            userID: 'notice',
            ex: '{"accountType":"official","officialRole":"pay"}'),
        FriendInfo(userID: 'ordinary', nickname: '99Pay'),
        FriendInfo(
            userID: 'assistant',
            ex: '{"accountType":"official","officialRole":"assistant"}'),
      ]);
      logic.groups.single.complete([]);
      await search;
      expect(
          logic.resultList.map((info) => (info as FriendInfo).userID),
          action == SelAction.forward
              ? ['99Message', 'notice', 'ordinary', 'assistant']
              : ['ordinary', 'assistant']);
      expect(
          logic.resultList
              .where((info) => !ContactSelectionPolicy.allows(info)),
          action == SelAction.forward ? hasLength(2) : isEmpty);
      logic.onClose();
    });
  }

  testWidgets(
      'late group membership lookup cannot modify selection after clear',
      (tester) async {
    final selection =
        Get.put<SelectContactsLogic>(_Selection(action: SelAction.addMember));
    await tester.pumpWidget(_overlay());
    final logic = _Search()..onInit();
    logic.searchCtrl.text = 'member';
    final search = logic.search();
    await tester.pump(const Duration(milliseconds: 2));
    logic.friends.single.complete([FriendInfo(userID: 'friend')]);
    await tester.pump();
    expect(logic.members, hasLength(1));
    logic.searchCtrl.clear();
    logic.members.single.complete([GroupMembersInfo(userID: 'friend')]);
    await search;
    expect(logic.resultList, isEmpty);
    expect(selection.defaultCheckedIDList, isEmpty);
    logic.onClose();
  });
}
