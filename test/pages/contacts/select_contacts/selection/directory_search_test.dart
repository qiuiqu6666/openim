import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/select_contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/contacts/select_contacts/group_list/group_list_view.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../friend_list/support/friend_picker_presence_fixture.dart';

ISUserInfo _friend(String id, String name, {String? remark}) =>
    ISUserInfo.fromJson({
      'userID': id,
      'nickname': name,
      'remark': remark,
      'tagIndex': 'A',
      'namePinyin': name == '小林' ? 'XIAO LIN' : name.toUpperCase(),
    });

Future<void> _query(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.pumpAndSettle();
}

Future<void> _clear(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate((widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == ImageRes.clearText));
  await tester.pumpAndSettle();
}

Future<void> _selectAll(WidgetTester tester) async {
  await tester.tap(find.text(StrRes.selectAll));
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} friend search preserves hidden selections',
        (tester) async {
      final data = [
        _friend('friend', '小林', remark: 'Alice 备注'),
        _friend('locked', 'Alice 默认已选'),
        _friend('other', '其他好友'),
      ];
      final fixture =
          FriendPickerPresenceFixture(action: SelAction.forward, data: data);
      fixture.selection.defaultCheckedIDList.add('locked');
      fixture.selection.checkedList['locked'] = data[1];
      await fixture.open(tester,
          brightness: brightness, width: 320, textScale: 2);
      expect(
          find.byKey(const ValueKey('select-friends-search')), findsOneWidget);
      await _query(tester, '  aLIce  ');
      expect(friendPickerRow('friend'), findsOneWidget);
      expect(friendPickerRow('other'), findsNothing);
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(), {'friend', 'locked'});

      await _query(tester, '其他');
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(),
          {'friend', 'locked', 'other'});
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(), {'friend', 'locked'});

      for (final query in ['小林', 'xiao lin', 'friend']) {
        await _query(tester, query);
        expect(friendPickerRow('friend'), findsOneWidget);
        expect(fixture.friends.visibleFriends.single.userID, 'friend');
      }
      await _query(tester, '没有匹配结果');
      expect(find.text(StrRes.searchNotFound), findsOneWidget);
      expect(fixture.friends.isSelectAll, isFalse);
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(), {'friend', 'locked'});
      await _clear(tester);
      expect(fixture.friends.visibleFriends, hasLength(3));
      expect(fixture.friends.searchController.text, isEmpty);
      expect(friendPickerRow('other'), findsOneWidget);
      await _query(tester, 'Alice');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse);
      expect(fixture.friends.friendList, orderedEquals(data));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} group select-all affects matching groups only',
        (tester) async {
      final fixture = FriendPickerPresenceFixture(action: SelAction.forward);
      await fixture.open(tester, brightness: brightness);
      final data = [
        GroupInfo(groupID: 'group', groupName: 'ALICE 项目群', memberCount: 8),
        GroupInfo(groupID: 'locked', groupName: 'Alice 默认已选', memberCount: 8),
        GroupInfo(groupID: 'other', groupName: '另一个群', memberCount: 9),
      ];
      fixture.selection.defaultCheckedIDList.add('locked');
      fixture.selection.checkedList['locked'] = data[1];
      var loads = 0;
      final groups = Get.put(
          SelectContactsFromGroupLogic(
              selection: fixture.selection,
              loadGroups: () async {
                loads++;
                return data;
              }),
          permanent: true);
      fixture.navigator.currentState!.push<void>(MaterialPageRoute(
          builder: (_) => SelectContactsFromGroupPage(
              logic: groups, selection: fixture.selection)));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('select-groups-search')), findsOneWidget);
      await _query(tester, ' aLiCe ');
      expect(find.byKey(const ValueKey('select-group-other')), findsNothing);
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(), {'locked', 'group'});
      await _query(tester, '另一个');
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(),
          {'locked', 'group', 'other'});
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(), {'locked', 'group'});
      await _query(tester, 'other');
      expect(groups.visibleGroups.single, same(data[2]));
      await _query(tester, '没有匹配结果');
      expect(find.text('未找到相关群聊'), findsOneWidget);
      expect(groups.isSelectAll, isFalse);
      await _selectAll(tester);
      expect(fixture.selection.checkedList.keys.toSet(), {'locked', 'group'});
      await _clear(tester);
      expect(groups.visibleGroups, orderedEquals(data));
      expect(groups.searchController.text, isEmpty);
      expect(loads, 1,
          reason: 'Typing and selecting must not reload the SDK directory.');
      await _query(tester, '项目');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse);
      await tester.tap(find.byKey(const ValueKey('select-contacts-back')));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys.toSet(), {'locked', 'group'});
      expect(
          find.byKey(const ValueKey('select-friends-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'friend search resets a scrolled alphabet list to its first match',
      (tester) async {
    final fixture =
        FriendPickerPresenceFixture(action: SelAction.forward, data: [
      for (var i = 0; i < 100; i++) _friend('$i', i == 0 ? 'Alice' : '好友$i'),
    ]);
    await fixture.open(tester);
    await tester.drag(friendPickerRow('3'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(friendPickerRow('0').hitTestable(), findsNothing);
    await _query(tester, 'Alice');
    expect(friendPickerRow('0').hitTestable(), findsOneWidget);
    expect(fixture.friends.visibleFriends, hasLength(1));
    await tester.tap(friendPickerRow('0'));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys, ['0']);
    expect(tester.takeException(), isNull);
  });
}
