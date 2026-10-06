import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/services/account_privilege/account_privilege_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_floating_entry.dart';
import 'support/profile_panel_fixture.dart';
import 'support/profile_panel_host.dart';
import '../../group_features/sangong/sangong_test_support.dart';

void main() {
  for (final dark in [false, true]) {
    for (final allowed in [false, true]) {
      testWidgets(
          'actual details uses viewer privilege with zero common groups, dark=$dark allowed=$allowed',
          (tester) async {
        OpenIM.iMManager.userID = 'owner';
        var profileReads = 0;
        final privilege = AccountPrivilegeStore(
            session: () => const AccountPrivilegeSession(
                userID: 'owner',
                chatToken: 'fixture-chat-token',
                baseUrl: 'https://fixture.example'),
            fetchProfile: (_) async {
              profileReads++;
              return UserFullInfo(userID: 'owner', isPrivileged: allowed);
            });
        final api = SangongTestApi();
        final store = GroupFeatureStore(
            api: api,
            accountPrivilege: privilege,
            sessionCurrent: () => true,
            fetchGroups: (_) async => []);
        // The displayed friend's own flag never grants the viewer access.
        final fixture = ProfilePanelFixture(
            user: UserFullInfo(
                userID: 'target',
                nickname: '秋啊',
                account: '3pwvy2b0jg',
                isFriendship: true,
                isPrivileged: !allowed));
        fixture.commonGroupCount.value = 0;
        final moments = profileMomentsRepository(peerUserId: 'target');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          privilege.dispose();
          moments.dispose();
        });
        await mountProfilePanel(tester,
            fixture: fixture,
            moments: moments,
            dark: dark,
            size: const Size(375, 812),
            groupFeatureStore: store,
            loadGameGroups: () async => []);
        expect(profileReads, 1);
        expect(find.text('秋啊'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('user_profile_voice')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('user_profile_message')), findsOneWidget);
        expect(find.byKey(const ValueKey('sangong-profile-services')),
            allowed ? findsOneWidget : findsNothing);
        if (allowed) {
          expect(find.text('暂无已加入的群聊，请加入群聊后重试'), findsOneWidget);
          expect(find.text('上分'), findsOneWidget);
          expect(
              find.byType(SangongProfileLedgerFloatingEntry), findsOneWidget);
        }
        expect(api.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
