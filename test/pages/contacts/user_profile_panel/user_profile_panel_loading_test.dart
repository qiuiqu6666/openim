import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/profile_panel_fixture.dart';
import 'support/profile_panel_host.dart';

class _PendingApi extends ProfileMomentsApi {
  final ready = Completer<MomentsCapabilities>();

  @override
  Future<MomentsCapabilities> capabilities() => ready.future;
}

MomentsRepository _pendingRepository(_PendingApi api) => MomentsRepository(
      api: api,
      userIdProvider: () => 'profile-test-owner',
      environmentProvider: () => 'https://profile-preview.example',
      friendLoader: () async =>
          [const MomentUser(userId: 'sdk-internal-peer-id')],
      privacySelectionStore:
          ProfilePrivacyStore(MomentsPrivacySelections.empty),
      subscribeToSdk: false,
    );

/// Measure each painted frame. Never settle away the first-frame transition.
Map<String, Rect?> _geometry(WidgetTester tester) {
  final values = <String, Rect?>{};
  void add(String name, Finder finder) => values[name] =
      finder.evaluate().isEmpty ? null : tester.getRect(finder.first);
  final identity = find.byKey(const ValueKey('user_profile_identity'));
  add('identity', identity);
  add('avatar',
      find.descendant(of: identity, matching: find.byType(AvatarView)));
  add('nickname', find.text('小林'));
  add('headerCard',
      find.ancestor(of: identity, matching: find.byType(SettingsGroup)));
  add('genderRow', find.widgetWithText(SettingsCell, StrRes.gender));
  add('voice', find.byKey(const ValueKey('user_profile_voice')));
  add('personal', find.byKey(const ValueKey('user_profile_personal_group')));
  add('commonGroups', find.byKey(const ValueKey('user_profile_common_groups')));
  add('scrollViewport', find.byType(ListView));
  add('appBar', find.byType(GlassAppBar));
  return values;
}

String _geometryChanges(Map<String, Rect?> first, Map<String, Rect?> next) {
  final changes = <String>[];
  for (final entry in first.entries) {
    final before = entry.value;
    final after = next[entry.key];
    if (before != null && after != null && before != after) {
      changes.add('${entry.key}: top ${after.top - before.top}, '
          'height ${after.height - before.height}');
    }
  }
  return changes.join('; ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  for (final dark in [false, true]) {
    for (final largeText in [false, true]) {
      for (final group in [false, true]) {
        testWidgets(
            'known ${group ? 'group ' : ''}friend stays still as account and multiline bio arrive ($dark, $largeText)',
            (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final fixture = ProfilePanelFixture(group: group);
            fixture.groupAccount.value = null;
            fixture.userInfo.update((user) {
              user?.account = null;
              user?.gender = null;
              user?.ex = null;
            });
            final contacts = ProfileContactsFixture();
            final api = _PendingApi();
            final repository = _pendingRepository(api);
            addTearDown(repository.dispose);
            addTearDown(contacts.stars.dispose);
            await mountProfilePanel(tester,
                fixture: fixture,
                moments: repository,
                contacts: contacts,
                dark: dark,
                size: largeText ? const Size(320, 812) : const Size(375, 812),
                textScale: largeText ? 2 : 1,
                settle: false);
            final first = _geometry(tester);
            expect(first['avatar'], isNotNull);
            expect(first['voice'], isNotNull);
            expect(
                find.byIcon(Icons.copy_outlined).hitTestable(), findsNothing);
            if (group) {
              expect(find.byIcon(Icons.copy_outlined), findsNothing);
              expect(find.bySemanticsLabel('复制聊天号'), findsNothing);
              expect(
                  find.bySemanticsLabel(RegExp('@ab12cd34ef')), findsNothing);
            }
            expect(
                tester
                    .widget<Scaffold>(find.byType(Scaffold))
                    .bottomNavigationBar,
                isNull);

            if (group) {
              fixture.groupAccount.value = '@ab12cd34ef';
            } else {
              fixture.userInfo
                  .update((user) => user?.account = 'public_peer_1024');
            }
            await tester.pump(const Duration(milliseconds: 16));
            final afterAccount = _geometry(tester);
            expect(afterAccount, first,
                reason:
                    'The later public chat ID must not move the avatar or cards. '
                    '${_geometryChanges(first, afterAccount)}');
            expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
            fixture.userInfo.update((user) => user?.gender = 2);
            await tester.pump(const Duration(milliseconds: 16));
            expect(_geometry(tester), first);
            fixture.userInfo
                .update((user) => user?.ex = '{"signature":"生活很慢，咖啡很香。"}');
            await tester.pump(const Duration(milliseconds: 16));
            expect(_geometry(tester), first);
            fixture.userInfo.update((user) => user?.ex =
                '{"signature":"这是一段加载完成之后才返回的较长个性签名，希望这个周末可以和朋友一起去喝咖啡。"}');
            await tester.pump(const Duration(milliseconds: 16));
            expect(_geometry(tester), first,
                reason: 'A two-line bio must use its reserved space.');
            api.ready.complete(
                MomentsCapabilities.fromJson({'supportsMoments': true}));
            await tester.pump(const Duration(milliseconds: 16));
            await tester.pump(const Duration(milliseconds: 16));
            expect(_geometry(tester), first);
            if (group) {
              fixture.groupAccount.value = null;
              await tester.pump(const Duration(milliseconds: 16));
              expect(find.text('@ab12cd34ef'), findsNothing);
              expect(
                  find.byIcon(Icons.copy_outlined).hitTestable(), findsNothing);
              expect(find.byIcon(Icons.copy_outlined), findsNothing);
              expect(find.bySemanticsLabel('复制聊天号'), findsNothing);
              expect(
                  find.bySemanticsLabel(RegExp('@ab12cd34ef')), findsNothing);
              expect(_geometry(tester), first,
                  reason: 'Clearing disclosure must keep the reserved layout.');
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        });
      }

      testWidgets(
          'compact group stranger stays still as raw account arrives ($dark, $largeText)',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final fixture = ProfilePanelFixture(friend: false, group: true);
          fixture.groupAccount.value = null;
          fixture.userInfo.update((user) {
            user?.gender = null;
            user?.ex = null;
          });
          final repository = profileMomentsRepository();
          addTearDown(repository.dispose);
          await mountProfilePanel(tester,
              fixture: fixture,
              moments: repository,
              dark: dark,
              size: largeText ? const Size(320, 812) : const Size(375, 812),
              textScale: largeText ? 2 : 1,
              settle: false);
          final first = _geometry(tester);
          expect(first['avatar'], isNotNull);
          expect(first['headerCard'], isNotNull);
          expect(first['genderRow'], isNotNull);
          Rect detailsCard() => tester.getRect(find
              .ancestor(
                  of: find.widgetWithText(SettingsCell, StrRes.gender),
                  matching: find.byType(SettingsGroup))
              .first);
          final detailsCardTop = detailsCard().top;
          void expectUndisclosed() {
            expect(find.text('profileChatID'.tr), findsNothing);
            expect(find.text('@ab12cd34ef'), findsNothing);
            expect(find.text('public_peer_1024'), findsNothing);
            expect(find.byIcon(Icons.copy_outlined), findsNothing);
            expect(find.bySemanticsLabel('复制聊天号'), findsNothing);
            expect(
                find.bySemanticsLabel(RegExp('@ab12cd34ef|public_peer_1024')),
                findsNothing);
            expect(fixture.copiedIds, isEmpty);
          }

          expectUndisclosed();
          fixture.groupAccount.value = '@ab12cd34ef';
          await tester.pump(const Duration(milliseconds: 16));
          final afterAccount = _geometry(tester);
          expect(afterAccount, first,
              reason:
                  'The compact header and details card top must stay still. '
                  '${_geometryChanges(first, afterAccount)}');
          expect(detailsCard().top, detailsCardTop);
          expect(find.text('profileChatID'.tr), findsOneWidget);
          expect(find.text('@ab12cd34ef'), findsWidgets);
          expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
          fixture.userInfo.update((user) =>
              user?.ex = '{"signature":"这是一段加载之后返回的个性签名，希望周末和朋友一起去喝咖啡。"}');
          await tester.pump(const Duration(milliseconds: 16));
          expect(_geometry(tester), first);
          expect(detailsCard().top, detailsCardTop);
          fixture.groupAccount.value = null;
          await tester.pump(const Duration(milliseconds: 16));
          expectUndisclosed();
          expect(_geometry(tester), first);
          expect(detailsCard().top, detailsCardTop);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets('unknown relationship waits before choosing its layout ($dark)',
        (tester) async {
      final fixture = ProfilePanelFixture(friend: false);
      fixture.profileLayoutReady.value = false;
      fixture.userInfo.update((user) {
        user?.account = null;
        user?.allowAddFriend = null;
        user?.ex = null;
      });
      final repository = profileMomentsRepository();
      addTearDown(repository.dispose);
      await mountProfilePanel(tester,
          fixture: fixture,
          moments: repository,
          dark: dark,
          size: const Size(320, 650),
          textScale: 2,
          settle: false);
      expect(
          find.byKey(const ValueKey('user_profile_loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('user_profile_identity')), findsNothing);
      expect(find.byType(Button), findsNothing);
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
          isNull);
      final navigation = tester.getRect(find.byType(GlassAppBar));
      fixture.userInfo.update((user) {
        user?.isFriendship = true;
        user?.account = 'public_peer_1024';
      });
      fixture.profileLayoutReady.value = true;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('user_profile_loading')), findsNothing);
      expect(find.byKey(const ValueKey('user_profile_voice')), findsOneWidget);
      expect(find.byType(Button), findsNothing);
      expect(tester.getRect(find.byType(GlassAppBar)), navigation);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'initial failure retries without pretending the user is a stranger ($dark)',
        (tester) async {
      final fixture = ProfilePanelFixture(friend: false);
      fixture.profileLayoutReady.value = false;
      fixture.initialProfileFailed.value = true;
      final repository = profileMomentsRepository();
      addTearDown(repository.dispose);
      await mountProfilePanel(tester,
          fixture: fixture,
          moments: repository,
          dark: dark,
          size: const Size(320, 650),
          textScale: 2,
          settle: false);
      expect(find.byType(Button), findsNothing);
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
          isNull);
      await tester.tap(find.byKey(const ValueKey('user_profile_retry')));
      await tester.pump(const Duration(milliseconds: 16));
      expect(fixture.actions, ['retryInitialProfile']);
      expect(
          find.byKey(const ValueKey('user_profile_loading')), findsOneWidget);
      fixture.userInfo.update((user) => user?.allowAddFriend = 1);
      fixture.profileLayoutReady.value = true;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('user_profile_retry')), findsNothing);
      expect(find.byType(Button), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
