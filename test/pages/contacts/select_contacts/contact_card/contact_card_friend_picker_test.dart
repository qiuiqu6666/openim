import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/select_contacts/contact_card/contact_card_friend_picker.dart';
import 'package:openim/pages/contacts/presence_label.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'support/contact_card_picker_fixture.dart';

Finder _friend(String id) => find.byKey(ValueKey('contact-card-friend-$id'));
Finder get _search => find.descendant(
    of: find.byKey(const ValueKey('contact-card-search')),
    matching: find.byType(TextField));
Finder get _cancel => find.byKey(const ValueKey('contact-card-cancel'));
Finder get _dialog => find.byType(ContactCardSendDialog);

List<ISUserInfo> _shown(WidgetTester tester) =>
    tester.widget<AzListView>(find.byType(AzListView)).data.cast<ISUserInfo>();

Future<void> _query(WidgetTester tester, String text) async {
  await tester.enterText(_search, text);
  await tester.pumpAndSettle();
}

Future<void> _clear(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate(
      (widget) => widget is ImageView && widget.name == ImageRes.clearText));
  await tester.pumpAndSettle();
}

Finder _dialogButton(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));

void main() {
  setUpAll(loadContactCardPickerPreviewFont);
  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    final interval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
        () => VisibilityDetectorController.instance.updateInterval = interval);
  });
  tearDown(Get.reset);

  testWidgets(
      'carte opens the friend list directly with search and cancellation',
      (tester) async {
    final fixture = ContactCardPickerFixture();
    await fixture.mount(tester);
    expect(find.byType(ContactCardFriendPicker), findsOneWidget);
    expect(find.text('选择朋友'), findsOneWidget);
    expect(_search, findsOneWidget);
    expect(_cancel, findsOneWidget);
    expect(find.text(StrRes.myFriend), findsNothing);
    expect(find.text(StrRes.myGroup), findsNothing);
    expect(find.text(StrRes.selectAll), findsNothing);
    expect(find.text(StrRes.determine), findsNothing);
    expect(find.byType(ChatRadio), findsNothing);
    expect(_shown(tester).map((friend) => friend.userID),
        ['1001', '1002', '2001', '3001']);
    await _query(tester, 'Ada');
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(find.byType(ContactCardFriendPicker), findsNothing);
    expect(find.text('父聊天页面'), findsOneWidget);
    expect(fixture.returns, 1);
    expect(fixture.result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'system back cancels the picker without returning a selected contact',
      (tester) async {
    final fixture = ContactCardPickerFixture();
    await fixture.mount(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ContactCardFriendPicker), findsNothing);
    expect(find.text('父聊天页面'), findsOneWidget);
    expect(fixture.returns, 1);
    expect(fixture.result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search uses remark, nickname and UID then clear restores the real list',
      (tester) async {
    final fixture = ContactCardPickerFixture();
    final original = List.of(fixture.friends.friendList);
    final originalJson = original.map((friend) => friend.toJson()).toList();
    final originalFlags =
        original.map((friend) => friend.isShowSuspension).toList();
    await fixture.mount(tester);
    for (final (query, id) in [
      (' aLiCe ', '1001'),
      ('ADA', '1002'),
      ('1002', '1002')
    ]) {
      await _query(tester, query);
      expect(_shown(tester).map((friend) => friend.userID), [id]);
      expect(_friend(id), findsOneWidget);
      await _clear(tester);
      expect(_shown(tester), hasLength(4));
    }
    await _query(tester, 'unmatched-contact');
    expect(find.byKey(const ValueKey('contact-card-empty')), findsOneWidget);
    expect(find.text('未找到相关联系人'), findsOneWidget);
    expect(find.byType(AzListView), findsNothing);
    await _clear(tester);
    expect(_shown(tester), hasLength(4));
    expect(fixture.friends.friendList, orderedEquals(original));
    expect(fixture.friends.friendList.map((friend) => friend.toJson()).toList(),
        originalJson);
    expect(
        fixture.friends.friendList
            .map((friend) => friend.isShowSuspension)
            .toList(),
        originalFlags);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'filtering the second member rebuilds its section without mutating source flags',
      (tester) async {
    final fixture = ContactCardPickerFixture();
    final source = fixture.friends.friendList[1];
    expect(source.isShowSuspension, isFalse);
    await fixture.mount(tester);
    await _query(tester, 'Lovelace');
    final result = _shown(tester).single;
    expect(result.userID, source.userID);
    expect(result, isNot(same(source)));
    expect(result.isShowSuspension, isTrue);
    expect(find.byKey(const ValueKey('contact-card-section-A')), findsWidgets);
    expect(source.isShowSuspension, isFalse);
    await _clear(tester);
    expect(_shown(tester)[1].isShowSuspension, isFalse);
    expect(source.isShowSuspension, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('friend deletion updates active search and restoring all rows',
      (tester) async {
    final fixture = ContactCardPickerFixture();
    await fixture.mount(tester);
    await _query(tester, 'Ada');
    expect(_friend('1002'), findsOneWidget);
    fixture.friends.friendList.removeWhere((friend) => friend.userID == '1002');
    await tester.pumpAndSettle();
    expect(_friend('1002'), findsNothing);
    expect(find.text('未找到相关联系人'), findsOneWidget);
    await _clear(tester);
    expect(_shown(tester).map((friend) => friend.userID),
        ['1001', '2001', '3001']);
    fixture.friends.friendList.clear();
    await tester.pumpAndSettle();
    expect(find.text('暂无联系人'), findsOneWidget);
    expect(find.byType(AzListView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dialog cancellation keeps the route and confirmation returns UserInfo',
      (tester) async {
    final fixture = ContactCardPickerFixture();
    await fixture.mount(tester);
    await tester.tap(_friend('1001'));
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(
        tester.widget<ContactCardSendDialog>(_dialog).recipientName, '当前聊天对象');
    await tester.tap(_dialogButton(StrRes.cancel));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(find.byType(ContactCardFriendPicker), findsOneWidget);
    expect(fixture.returns, 0);
    await tester.tap(_friend('1001'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton(StrRes.determine));
    await tester.pumpAndSettle();
    expect(find.byType(ContactCardFriendPicker), findsNothing);
    expect(fixture.returns, 1);
    expect(fixture.result, isA<UserInfo>());
    expect(fixture.result!.userID, '1001');
    expect(fixture.result!.nickname, 'Alberto');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rapid row taps open one confirmation and return to the parent once',
      (tester) async {
    final fixture = ContactCardPickerFixture();
    await fixture.mount(tester);
    final secondTap = tester.widget<InkWell>(_friend('1002')).onTap!;
    await tester.tap(_friend('1001'));
    // Deliver an already-dispatched second callback after the first opened its
    // modal, so this exercises the selection guard rather than the barrier.
    secondTap();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(tester.widget<ContactCardSendDialog>(_dialog).name, 'Alberto');
    await tester.tap(_dialogButton(StrRes.determine));
    await tester.pumpAndSettle();
    expect(fixture.result!.userID, '1001');
    expect(fixture.returns, 1);
    expect(find.text('父聊天页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stars update live while remote and local presence privacy stay enforced',
      (tester) async {
    final fixture = ContactCardPickerFixture(withPresence: true);
    await fixture.mount(tester);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(
        find.byKey(const ValueKey('contact-card-online-1001')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('contact-card-online-2001')), findsNothing);
    expect(find.descendant(of: _friend('2001'), matching: find.text('最近曾在线')),
        findsOneWidget);
    expect(find.descendant(of: _friend('2001'), matching: find.text('在线')),
        findsNothing);
    expect(
        find.descendant(
            of: _friend('1002'), matching: find.textContaining('小时前在线')),
        findsOneWidget);
    fixture.contacts!.stars.records['1002'] = StarFriend.fromJson({
      'friendUserID': '1002',
      'starred': true,
      'version': 1,
      'updatedAt': 30,
    });
    await tester.pumpAndSettle();
    expect(_shown(tester).first.userID, '1002');
    expect(_shown(tester).first.tagIndex, '★');
    expect(fixture.friends.friendList.first.userID, '1001');
    expect(fixture.friends.friendList[1].tagIndex, 'A');
    expect(find.byIcon(Icons.star), findsNWidgets(2));

    FriendDisplayPreferences.setOnlineStatus(false);
    await tester.pumpAndSettle();
    expect(find.byType(PresenceLabel), findsNothing);
    expect(
        find.byKey(const ValueKey('contact-card-online-1001')), findsNothing);
    expect(find.byIcon(Icons.star), findsNWidgets(2));
    expect(fixture.contacts!.presence.users['2001']!.online, isTrue);
    FriendDisplayPreferences.setOnlineStatus(true);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('contact-card-online-1001')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('contact-card-online-2001')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'visible presence belongs to the picker and pauses on dialog coverage without touching the directory',
      (tester) async {
    final fixture = ContactCardPickerFixture(withPresence: true);
    final contacts = fixture.contacts!;
    final mainOwner = Object();
    contacts
        .setDirectoryPresenceVisible(mainOwner, {'1001', 'directory-friend'});
    await fixture.mount(tester);
    final pickerOwner =
        contacts.owners.keys.singleWhere((owner) => owner != mainOwner);
    expect(contacts.owners[pickerOwner],
        containsAll(['1001', '1002', '2001', '3001']));
    await _query(tester, 'Ada');
    expect(contacts.owners[pickerOwner], {'1002'});
    expect(contacts.owners[mainOwner], {'1001', 'directory-friend'});
    await tester.tap(_friend('1002'));
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(contacts.owners[pickerOwner], isEmpty);
    expect(contacts.owners[mainOwner], {'1001', 'directory-friend'});
    await tester.tap(_dialogButton(StrRes.cancel));
    await tester.pumpAndSettle();
    expect(contacts.owners[pickerOwner], {'1002'});
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(contacts.owners.containsKey(pickerOwner), isFalse);
    expect(contacts.owners[mainOwner], {'1001', 'directory-friend'});
    expect(
        contacts.batches.lastWhere((batch) => batch.owner == pickerOwner).ids,
        isNull);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} narrow large text keeps search, cancellation and friend actions usable',
        (tester) async {
      final fixture = ContactCardPickerFixture(withPresence: true);
      await fixture.mount(tester,
          brightness: brightness, size: const Size(320, 568), textScale: 2);
      expect(find.text('选择朋友'), findsOneWidget);
      for (final control in [_search, _cancel, _friend('1001')]) {
        expect(control.hitTestable(), findsOneWidget);
        final rect = tester.getRect(control);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      expect(tester.getSize(_friend('1001')).height, greaterThanOrEqualTo(64));
      await captureContactCardPicker(tester, brightness, large: true);
      await tester.tap(_friend('1001'));
      await tester.pumpAndSettle();
      expect(_dialog, findsOneWidget);
      final dialogRect = tester.getRect(find.byType(Dialog));
      expect(dialogRect.left, greaterThanOrEqualTo(0));
      expect(dialogRect.right, lessThanOrEqualTo(320));
      await tester.tap(_dialogButton(StrRes.cancel));
      await tester.pumpAndSettle();
      expect(find.byType(ContactCardFriendPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  if (const bool.fromEnvironment('CONTACT_CARD_PICKER_PREVIEW')) {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} normal size visual preview',
          (tester) async {
        final fixture = ContactCardPickerFixture(withPresence: true);
        await fixture.mount(tester,
            brightness: brightness, size: const Size(375, 812));
        expect(tester.takeException(), isNull);
        await captureContactCardPicker(tester, brightness);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
