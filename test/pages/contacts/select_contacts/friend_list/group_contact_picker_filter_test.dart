import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/friend_list_view.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim_common/openim_common.dart';

import 'support/friend_picker_presence_fixture.dart';

ISUserInfo _friend(String id, {String? nickname, String? ex}) =>
    ISUserInfo.fromJson({
      'userID': id,
      'nickname': nickname ?? id,
      'tagIndex': 'A',
      'ex': ex,
    });

List<ISUserInfo> _samples() => [
      _friend('assistant', nickname: 'AI助理'),
      _friend('official-service',
          nickname: '服务助手',
          ex: '{"accountType":"official","officialRole":"assistant"}'),
      _friend('99Message'),
      _friend('99Pay'),
      _friend('ordinary', nickname: 'AI助理'),
      _friend('friend', nickname: 'Alice'),
    ];

Finder _row(SelAction action, String id) => action == SelAction.crateGroup
    ? find.byKey(ValueKey('group-picker-$id'))
    : friendPickerRow(id);

Future<FriendPickerPresenceFixture> _openPicker(
    WidgetTester tester, SelAction action,
    {Brightness brightness = Brightness.light}) async {
  final fixture = FriendPickerPresenceFixture(
      action: action == SelAction.crateGroup ? SelAction.addMember : action,
      data: _samples());
  await fixture.open(tester, brightness: brightness);
  if (action == SelAction.crateGroup) {
    // The shared fixture only fakes directory presence. The creation picker
    // uses the legacy single-user presence API, so mount it without that store.
    await Get.delete<ContactsLogic>(force: true);
    fixture.selection.action = action;
    fixture.navigator.currentState!.pushReplacement<Object?, void>(
        MaterialPageRoute<Object?>(
            builder: (_) => SelectContactsFromFriendsPage()));
    await tester.pumpAndSettle();
  }
  return fixture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in [SelAction.crateGroup, SelAction.addMember]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '${action.name} ${brightness.name} hides official AI but keeps a same-name friend',
          (tester) async {
        final fixture =
            await _openPicker(tester, action, brightness: brightness);
        for (final id in [
          'assistant',
          'official-service',
          '99Message',
          '99Pay'
        ]) {
          expect(_row(action, id), findsNothing);
        }
        expect(_row(action, 'ordinary'), findsOneWidget);
        expect(_row(action, 'friend'), findsOneWidget);
        expect(find.text('AI助理'), findsOneWidget);
        expect(fixture.friends.friendList, hasLength(6),
            reason: 'Filtering the picker must keep the SDK source directory.');

        await tester.enterText(find.byType(TextField), 'AI助理');
        await tester.pumpAndSettle();
        expect(_row(action, 'assistant'), findsNothing);
        expect(_row(action, 'ordinary'), findsOneWidget);
        expect(_row(action, 'friend'), findsNothing);
        await tester.tap(_row(action, 'ordinary'));
        await tester.pumpAndSettle();
        expect(fixture.selection.checkedList.keys, ['ordinary']);

        await tester.enterText(find.byType(TextField), 'assistant');
        await tester.pumpAndSettle();
        expect(_row(action, 'assistant'), findsNothing);
        expect(_row(action, 'ordinary'), findsNothing);
        expect(fixture.selection.checkedList.keys, ['ordinary']);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${action.name} select-all excludes every official account',
        (tester) async {
      final fixture = await _openPicker(tester, action);
      fixture.friends.selectAll();
      await tester.pumpAndSettle();
      expect(
          fixture.selection.checkedList.keys.toSet(), {'ordinary', 'friend'});
      expect(fixture.friends.isSelectAll, isTrue);
      fixture.friends.selectAll();
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList, isEmpty);

      fixture.friends.searchFriends('AI助理');
      fixture.friends.selectAll();
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys, ['ordinary']);
      fixture.friends.searchFriends('assistant');
      expect(fixture.friends.operableList, isEmpty);
      fixture.friends.selectAll();
      expect(fixture.selection.checkedList.keys, ['ordinary']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${action.name} cleans route preselection and submitted members',
        (tester) async {
      Get.testMode = true;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        Get.reset();
      });
      await tester
          .pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('父页面'))));
      await tester.pumpAndSettle();
      late SelectContactsLogic selection;
      final samples = _samples();
      final result = Get.to<Map<String, dynamic>>(
        () => const Scaffold(body: Text('选择群成员')),
        arguments: {
          'action': action,
          'defaultCheckedIDList': ['assistant', '99Message', '99Pay', 'friend'],
          'checkedList': {
            for (final friend in samples) friend.userID!: friend,
          },
          'openSelectedSheet': false,
        },
        binding: BindingsBuilder(() {
          selection = Get.put<SelectContactsLogic>(SelectContactsLogic());
        }),
        transition: Transition.noTransition,
      );
      await tester.pumpAndSettle();
      expect(selection.defaultCheckedIDList, {'friend'});
      expect(selection.checkedList.keys.toSet(), {'ordinary', 'friend'});
      for (final blocked in samples.take(4)) {
        expect(selection.onTap(blocked), isNull);
        selection.toggleChecked(blocked);
        await selection.confirmSelectedItem(blocked);
      }
      expect(selection.checkedList.keys.toSet(), {'ordinary', 'friend'});

      // Defend the final submission against stale entries inserted directly
      // after route initialization, as happens with restored picker state.
      selection.checkedList.assignAll({
        for (final friend in samples.take(4)) friend.userID!: friend,
      });
      expect(selection.enabledConfirmButton, isFalse);
      expect(selection.isChecked(samples.first), isFalse);
      selection.toggleChecked(samples[4]);
      expect(selection.enabledConfirmButton, isTrue);
      await selection.confirmSelectedList();
      await tester.pumpAndSettle();
      expect((await result)!.keys, ['ordinary']);
      expect(selection.checkedList.keys, ['ordinary']);
      expect(find.text('父页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
