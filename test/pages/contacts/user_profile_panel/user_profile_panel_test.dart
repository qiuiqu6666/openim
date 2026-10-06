import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/star_burst_button.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/pages/moments/moments_page.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/profile_panel_fixture.dart';
import 'support/profile_panel_host.dart';
import '../../moments/support/moments_ui_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey('user_profile_$name'));

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find.byType(Scrollable).first);
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  testWidgets('rapid Moments taps open one album and return to the profile',
      (tester) async {
    final fixture = ProfilePanelFixture();
    final moments = MomentsUiFixture(posts: []);
    addTearDown(moments.dispose);
    await mountProfilePanel(tester,
        fixture: fixture, moments: moments.repository);
    await _reveal(tester, _key('moments'));
    final row = tester.widget<SettingsCell>(_key('moments'));
    row.onTap!();
    row.onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(MomentsPage, skipOffstage: false), findsOneWidget);
    expect(tester.widget<MomentsPage>(find.byType(MomentsPage)).authorId,
        fixture.userInfo.value.userID);
    Navigator.of(tester.element(find.byType(MomentsPage))).pop();
    await tester.pumpAndSettle();
    expect(_key('identity'), findsOneWidget);
    expect(find.byType(MomentsPage, skipOffstage: false), findsNothing);
    row.onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(MomentsPage, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    testWidgets('friend groups and actions work in ${dark ? 'dark' : 'light'}',
        (tester) async {
      final fixture = ProfilePanelFixture();
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      await mountProfilePanel(tester,
          fixture: fixture, moments: moments, dark: dark);
      expect(_key('identity'), findsOneWidget);
      expect(find.text('小林'), findsOneWidget);
      expect(find.text('生活很慢，咖啡很香。'), findsOneWidget);
      expect(find.text('public_peer_1024'), findsOneWidget);
      expect(find.text('sdk-internal-peer-id'), findsNothing);
      final copyTarget = find.widgetWithText(InkWell, 'public_peer_1024');
      expect(tester.getSize(copyTarget).height, greaterThanOrEqualTo(48));
      expect(
          find.descendant(of: _key('personal_group'), matching: _key('remark')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _key('conversation_group'), matching: _key('common_groups')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _key('conversation_group'), matching: _key('background')),
          findsOneWidget);
      final primarySurface = tester.widget<Material>(_key('message')).color!;
      final primaryLabel = tester.widget<Text>(find.descendant(
          of: _key('message'), matching: find.text(StrRes.sendMessage)));
      final foreground = primaryLabel.style!.color!.computeLuminance();
      final background = primarySurface.computeLuminance();
      final contrast = foreground > background
          ? (foreground + .05) / (background + .05)
          : (background + .05) / (foreground + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      for (final action in ['voice', 'video', 'message']) {
        await _tap(tester, _key(action));
      }
      for (final action in ['remark', 'common_groups', 'background']) {
        await _tap(tester, _key(action));
      }
      expect(fixture.actions,
          ['voice', 'video', 'chat', 'remark', 'commonGroups', 'background']);
      await _tap(tester, find.byIcon(Icons.copy_outlined));
      expect(fixture.copiedIds, ['public_peer_1024']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('common groups distinguish count, loading and failure ($dark)',
        (tester) async {
      final fixture = ProfilePanelFixture();
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      await mountProfilePanel(tester,
          fixture: fixture, moments: moments, dark: dark);
      SettingsCell cell() => tester.widget<SettingsCell>(_key('common_groups'));
      expect(cell().value, '3');
      fixture.commonGroupCount.value = 0;
      await tester.pump();
      expect(cell().value, '0');
      fixture.loadingCommonGroups.value = true;
      await tester.pump();
      expect(cell().value, 'profileCommonGroupsLoading'.tr);
      fixture.loadingCommonGroups.value = false;
      fixture.commonGroupsFailed.value = true;
      await tester.pump();
      expect(cell().value, 'profileCommonGroupsCountFailed'.tr);
      await _tap(tester, _key('common_groups'));
      expect(fixture.actions, ['commonGroups']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final friend in [true, false]) {
      testWidgets(
          'profile navigation matches the page and stays fixed ($dark/$friend)',
          (tester) async {
        final fixture = ProfilePanelFixture(friend: friend, group: !friend);
        final moments = profileMomentsRepository();
        addTearDown(moments.dispose);
        await mountProfilePanel(tester,
            fixture: fixture, moments: moments, dark: dark);
        final appBar = find.byType(GlassAppBar);
        expect(appBar, findsOneWidget);
        final background =
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
        expect(background, isNotNull);
        expect(background!.a, 1);
        expect(tester.widget<GlassAppBar>(appBar).backgroundColor, background);
        final navigationSurface = tester.widget<Material>(
            find.descendant(of: appBar, matching: find.byType(Material)).first);
        expect(navigationSurface.color, background);
        expect(
            find.descendant(
                of: appBar, matching: find.byType(LiquidGlassSurface)),
            findsNothing);
        expect(
            find.descendant(of: appBar, matching: find.byType(BackdropFilter)),
            findsNothing);
        final initial = tester.getRect(appBar);
        final avatar = find.descendant(
            of: _key('identity'), matching: find.byType(AvatarView));
        expect(
            tester.getRect(avatar).top, greaterThanOrEqualTo(initial.bottom));
        await tester.drag(find.byType(ListView).first, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.getRect(appBar), initial);
        expect(Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile),
            same(fixture));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('friend relationship changes rebuild actions without new logic',
      (tester) async {
    final fixture = ProfilePanelFixture(friend: false);
    final moments = profileMomentsRepository();
    addTearDown(moments.dispose);
    await mountProfilePanel(tester, fixture: fixture, moments: moments);
    expect(find.text(StrRes.addFriend), findsOneWidget);
    expect(_key('voice'), findsNothing);
    fixture.userInfo.update((user) => user?.isFriendship = true);
    await tester.pumpAndSettle();
    expect(find.text(StrRes.addFriend), findsNothing);
    expect(_key('voice'), findsOneWidget);
    expect(_key('remark'), findsOneWidget);
    fixture.userInfo.update((user) => user?.isFriendship = false);
    await tester.pumpAndSettle();
    expect(_key('voice'), findsNothing);
    expect(_key('remark'), findsNothing);
    expect(find.text(StrRes.addFriend), findsOneWidget);
    expect(Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile),
        same(fixture));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final friend in [false, true]) {
    testWidgets(
        'self profile preserves personal info and hides peer actions ($friend)',
        (tester) async {
      final fixture = ProfilePanelFixture(self: true, friend: friend);
      final contacts = ProfileContactsFixture();
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      addTearDown(contacts.stars.dispose);
      await mountProfilePanel(tester,
          fixture: fixture, moments: moments, contacts: contacts);
      expect(find.text(StrRes.personalInfo), findsOneWidget);
      expect(find.text('朋友圈'), findsOneWidget);
      expect(_key('voice'), findsNothing);
      expect(_key('video'), findsNothing);
      expect(_key('message'), findsNothing);
      expect(_key('common_groups'), findsNothing);
      expect(_key('blacklist'), findsNothing);
      expect(find.text(StrRes.addFriend), findsNothing);
      expect(find.byType(StarBurstButton), findsNothing);
      await _tap(tester, find.text(StrRes.personalInfo));
      expect(fixture.actions, ['personalInfo']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('group add protection does not hide a returned public account',
      (tester) async {
    final fixture = ProfilePanelFixture(friend: false, group: true);
    fixture.userInfo.update((user) => user?.allowAddFriend = 2);
    fixture.iAmOwner.value = true;
    fixture.notAllowAddGroupMemberFriend.value = true;
    final moments = profileMomentsRepository();
    addTearDown(moments.dispose);
    await mountProfilePanel(tester, fixture: fixture, moments: moments);
    expect(find.text('public_peer_1024'), findsWidgets);
    expect(find.text('sdk-internal-peer-id'), findsNothing);
    expect(find.text('profileChatID'.tr), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    await _tap(tester, find.text(StrRes.addFriend));
    expect(fixture.actions, ['add']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'empty public account never falls back to internal SDK identifier',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = ProfilePanelFixture();
      fixture.userInfo.update((user) => user?.account = '');
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      await mountProfilePanel(tester, fixture: fixture, moments: moments);
      expect(find.text('sdk-internal-peer-id'), findsNothing);
      expect(find.byIcon(Icons.copy_outlined).hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('复制聊天号'), findsNothing);
      expect(fixture.copiedIds, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  for (final relationship in ['stranger', 'friend', 'self']) {
    testWidgets('group $relationship shows and copies only its group account',
        (tester) async {
      final fixture = ProfilePanelFixture(
        friend: relationship == 'friend',
        self: relationship == 'self',
        group: true,
      );
      fixture.groupAccount.value = null;
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      await mountProfilePanel(tester, fixture: fixture, moments: moments);
      expect(find.text('profileChatID'.tr), findsNothing);
      expect(find.text('public_peer_1024'), findsNothing);
      expect(find.text('sdk-internal-peer-id'), findsNothing);
      expect(find.byIcon(Icons.copy_outlined), findsNothing);
      expect(fixture.copiedIds, isEmpty);

      fixture.groupAccount.value = '@ab12cd34ef';
      await tester.pumpAndSettle();
      expect(find.text('@ab12cd34ef'), findsWidgets);
      expect(find.text('public_peer_1024'), findsNothing);
      await _tap(tester, find.byIcon(Icons.copy_outlined));
      expect(fixture.copiedIds, ['@ab12cd34ef']);
      if (relationship == 'stranger') {
        await _tap(tester, find.text('profileChatID'.tr));
        expect(fixture.copiedIds, ['@ab12cd34ef', '@ab12cd34ef']);
      }

      fixture.groupAccount.value = '';
      await tester.pumpAndSettle();
      expect(find.text('profileChatID'.tr), findsNothing);
      expect(find.text('@ab12cd34ef'), findsNothing);
      expect(find.byIcon(Icons.copy_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('closed group member context hides the add action',
      (tester) async {
    final fixture = ProfilePanelFixture(friend: false, group: true);
    final moments = profileMomentsRepository();
    addTearDown(moments.dispose);
    await mountProfilePanel(tester, fixture: fixture, moments: moments);
    expect(find.text(StrRes.addFriend), findsOneWidget);
    fixture.activeGroupContext.value = false;
    await tester.pump();
    expect(find.text(StrRes.addFriend), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    testWidgets(
        'chat entry prepares a public account without extra hints ($dark)',
        (tester) async {
      final fixture = ProfilePanelFixture(friend: false);
      fixture.friendAddEntry.value = false;
      fixture.userInfo.update((user) => user?.account = 'ab12345678');
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      await mountProfilePanel(tester,
          fixture: fixture, moments: moments, dark: dark);
      expect(find.text(StrRes.addFriend), findsOneWidget);
      expect(find.text('通过99号添加'), findsNothing);
      expect(fixture.canPrepareFriendAdd, isTrue);
      expect(_key('add_method_hint'), findsNothing);
      expect(find.textContaining('凭证'), findsNothing);
      expect(find.textContaining('grant'), findsNothing);
      fixture.preparingFriendAdd.value = true;
      await tester.pump();
      final busyAdd = tester.widget<Button>(find.ancestor(
          of: find.text(StrRes.addFriend), matching: find.byType(Button)));
      expect(busyAdd.enabled, isFalse);
      await _tap(tester, find.text(StrRes.addFriend));
      expect(fixture.actions, isEmpty);
      fixture.preparingFriendAdd.value = false;
      await tester.pump();
      await _tap(tester, find.text(StrRes.addFriend));
      expect(fixture.actions, ['add']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final english in [false, true]) {
    testWidgets('missing public account asks for QR code or card ($english)',
        (tester) async {
      final fixture = ProfilePanelFixture(friend: false);
      fixture.friendAddEntry.value = false;
      fixture.userInfo.update((user) => user?.account = null);
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      await mountProfilePanel(tester,
          fixture: fixture,
          moments: moments,
          locale:
              english ? const Locale('en', 'US') : const Locale('zh', 'CN'));
      expect(fixture.canPrepareFriendAdd, isFalse);
      expect(_key('add_method_hint'), findsOneWidget);
      expect(
          find.text(english
              ? 'This person has not shared their chat ID. Ask them to share a QR code or contact card.'
              : '对方未公开聊天号，请让对方分享二维码或名片。'),
          findsOneWidget);
      expect(find.text(StrRes.addFriend), findsOneWidget);
      expect(find.textContaining('搜索'), findsNothing);
      expect(find.textContaining('凭证'), findsNothing);
      expect(find.textContaining('grant'), findsNothing);
      expect(find.text('sdk-internal-peer-id'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('blacklist pending disables friend switch and stranger actions',
      (tester) async {
    final fixture = ProfilePanelFixture();
    final moments = profileMomentsRepository();
    addTearDown(moments.dispose);
    await mountProfilePanel(tester, fixture: fixture, moments: moments);
    fixture.updatingBlacklist.value = true;
    await tester.pump();
    final switches = find.descendant(
        of: _key('blacklist'), matching: find.byType(CupertinoSwitch));
    expect(tester.widget<CupertinoSwitch>(switches).onChanged, isNull);
    fixture.userInfo.update((user) => user?.isFriendship = false);
    await tester.pumpAndSettle();
    final add = tester.widget<Button>(find.ancestor(
        of: find.text(StrRes.addFriend), matching: find.byType(Button)));
    final block = tester.widget<Button>(find.ancestor(
        of: find.text('profileAddBlacklist'.tr),
        matching: find.byType(Button)));
    expect(add.enabled, isFalse);
    expect(block.enabled, isFalse);
    await _tap(tester, find.text(StrRes.addFriend));
    await _tap(tester, find.text('profileAddBlacklist'.tr));
    expect(fixture.actions, isEmpty);
    expect(fixture.blacklistRequests, isEmpty);
    fixture.updatingBlacklist.value = false;
    await tester.pump();
    await _tap(tester, find.text('profileAddBlacklist'.tr));
    expect(fixture.blacklistRequests, [true]);
    expect(find.text('profileRemoveBlacklist'.tr), findsOneWidget);
    final blockedAdd = tester.widget<Button>(find.ancestor(
        of: find.text(StrRes.addFriend), matching: find.byType(Button)));
    expect(blockedAdd.enabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('star remains selected and blocks repeated pending action',
      (tester) async {
    final fixture = ProfilePanelFixture();
    final contacts = ProfileContactsFixture();
    final moments = profileMomentsRepository();
    addTearDown(moments.dispose);
    addTearDown(contacts.stars.dispose);
    await mountProfilePanel(tester,
        fixture: fixture, moments: moments, contacts: contacts);
    await _tap(tester, find.byType(StarBurstButton));
    expect(contacts.stars.toggledIds, ['sdk-internal-peer-id']);
    expect(tester.widget<StarBurstButton>(find.byType(StarBurstButton)).starred,
        isTrue);
    contacts.stars.pending.add('sdk-internal-peer-id');
    await tester.pump();
    expect(
        tester.widget<StarBurstButton>(find.byType(StarBurstButton)).onPressed,
        isNull);
    await _tap(tester, find.byType(StarBurstButton));
    expect(contacts.stars.toggledIds, ['sdk-internal-peer-id']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(320, 650),
    const Size(812, 375),
    const Size(1024, 768)
  ]) {
    testWidgets('long English text and large font fit $size', (tester) async {
      final fixture = ProfilePanelFixture();
      fixture.userInfo.update((user) {
        user?.nickname = 'An unusually long original contact nickname';
        user?.remark = 'An unusually long private remark for this contact';
        user?.account = 'public-account-name-with-many-characters';
        user?.ex =
            '{"signature":"A long biography explaining a very relaxed weekend with friends and coffee."}';
      });
      final moments = profileMomentsRepository();
      addTearDown(moments.dispose);
      final contacts = ProfileContactsFixture();
      addTearDown(contacts.stars.dispose);
      await mountProfilePanel(tester,
          fixture: fixture,
          moments: moments,
          contacts: contacts,
          size: size,
          dark: true,
          locale: const Locale('en', 'US'),
          textScale: 2,
          reducedMotion: true);
      for (final action in ['voice', 'video', 'message', 'blacklist']) {
        await _reveal(tester, _key(action));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
