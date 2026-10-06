import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_team_page.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_authorized_view.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_panel.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_submit_cutoff.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_bet_preview_sheet.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_round_settle_dialog.dart';
import '../sangong_test_support.dart';

class _PendingPrivilege extends FixtureAccountPrivilege {
  final result = Completer<bool>();
  @override
  Future<bool> refresh() {
    refreshCount++;
    return result.future;
  }
}

GroupFeatureContext _withPrivilege(
    SangongTestApi api, FixtureAccountPrivilege privilege) {
  final base = sangongTestContext(api);
  return GroupFeatureContext(
    groupID: base.groupID,
    groupName: base.groupName,
    currentUserID: base.currentUserID,
    api: api,
    accountPrivilege: privilege,
    features: base.features,
    capabilities: base.capabilities,
    sessionCurrent: base.sessionCurrent,
    capabilitiesCurrent: base.capabilitiesCurrent,
    onFeaturesChanged: base.onFeaturesChanged,
  );
}

Future<void> _chat(WidgetTester tester, SangongRuntime runtime,
        {bool dark = false}) =>
    pumpSangongPage(tester, runtime, const Scaffold(body: Text('普通聊天')),
        dark: dark);

void main() {
  for (final dark in [false, true]) {
    testWidgets('revocation closes two game pages and their dialog, dark=$dark',
        (tester) async {
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _chat(tester, runtime, dark: dark);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final first = navigator.push<void>(SangongPageRoute(
        context: tester.element(find.text('普通聊天')),
        builder: (_) => const Scaffold(body: Text('三公一级页面')),
      ));
      await tester.pumpAndSettle();
      final second = navigator.push<void>(SangongPageRoute(
        context: tester.element(find.text('三公一级页面')),
        builder: (_) => const Scaffold(body: Text('三公二级页面')),
      ));
      await tester.pumpAndSettle();
      final dialog = AppDialog.confirm(
        context: tester.element(find.text('三公二级页面')),
        title: '确认划转',
        message: '受保护的用户及金额',
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(api.privilege.refreshCount, 2);
      api.privilege.setAllowed(false);
      // Restoring the flag before rendering must not revive any old route.
      api.privilege.setAllowed(true);
      await tester.pumpAndSettle();
      await first;
      await second;
      expect(await dialog, isFalse);
      expect(find.text('普通聊天'), findsOneWidget);
      expect(find.text('三公一级页面', skipOffstage: false), findsNothing);
      expect(find.text('三公二级页面', skipOffstage: false), findsNothing);
      expect(
          find.byType(CupertinoAlertDialog, skipOffstage: false), findsNothing);
      expect(navigator.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a denied direct game route refreshes before any business read',
      (tester) async {
    final api = SangongTestApi();
    api.privilege.setAllowed(false);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _chat(tester, runtime);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final route = navigator.push<void>(SangongPageRoute(
      context: tester.element(find.text('普通聊天')),
      builder: (_) => const SangongAgentTeamPage(),
    ));
    await tester.pumpAndSettle();
    await route;
    expect(api.privilege.refreshCount, 1);
    expect(api.calls, isEmpty);
    expect(find.text('普通聊天'), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final failed in [false, true]) {
    testWidgets(
        'pending entry verification blocks cached grants, failed=$failed',
        (tester) async {
      final api = SangongTestApi();
      final privilege = _PendingPrivilege();
      final runtime = sangongTestRuntime(_withPrivilege(api, privilege));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _chat(tester, runtime);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final route = navigator.push<void>(SangongPageRoute(
        context: tester.element(find.text('普通聊天')),
        builder: (_) => const SangongAgentTeamPage(),
      ));
      await flushSangong(tester);
      expect(privilege.refreshCount, 1);
      expect(api.calls, isEmpty);
      expect(find.text('团队查询'), findsNothing);
      if (failed) {
        privilege.result.completeError(StateError('profile unavailable'));
      } else {
        privilege.setAllowed(false);
        privilege.result.complete(false);
      }
      await tester.pumpAndSettle();
      await route;
      expect(api.calls, isEmpty);
      expect(find.text('普通聊天'), findsOneWidget);
      expect(navigator.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a covered game route cannot pop an unrelated ordinary page',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _chat(tester, runtime);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final game = navigator.push<void>(SangongPageRoute(
      context: tester.element(find.text('普通聊天')),
      builder: (_) => const Scaffold(body: Text('被覆盖的三公页面')),
    ));
    await tester.pumpAndSettle();
    navigator.push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('普通用户资料'))));
    await tester.pumpAndSettle();
    api.privilege.setAllowed(false);
    await tester.pumpAndSettle();
    await game;
    expect(find.text('普通用户资料'), findsOneWidget);
    expect(find.text('被覆盖的三公页面', skipOffstage: false), findsNothing);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('普通聊天'), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile revocation closes its game dialog and preserves profile',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/reports/users')) {
          return {
            'users': [
              {'userId': 19, 'imUserId': 'im_target', 'balance': 420}
            ],
            'page': 1,
            'totalPages': 1,
          };
        }
        if (call.path.endsWith('/user-detail')) return <String, dynamic>{};
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              const Text('普通用户资料'),
              SangongAuthorizedView(
                  runtime: runtime,
                  child: const SangongProfilePanel(userID: 'im_target')),
            ]),
          ),
        ));
    expect(find.textContaining('当前积分 420'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.tap(find.text('上分'));
    // Inline inputs are confirmed in a guarded dialog before any write.
    await tester.pump(const Duration(milliseconds: 350));
    await flushSangong(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    api.privilege.setAllowed(false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    expect(find.textContaining('当前积分 420'), findsNothing);
    expect(find.text('普通用户资料'), findsOneWidget);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
    expect(api.count('/credit'), 0);
    expect(tester.takeException(), isNull);
  });

  for (final sheet in ['preview', 'settle']) {
    testWidgets('revocation closes the actual $sheet game sheet',
        (tester) async {
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _chat(tester, runtime);
      final context = tester.element(find.text('普通聊天'));
      final Future<Object?> result;
      if (sheet == 'preview') {
        result = SangongBetPreviewSheet.show(context,
            preview: const SangongBetPreview(),
            cutoff: const SangongBetSubmitCutoff(),
            roundId: 18,
            doorCount: 6);
      } else {
        result = SangongRoundSettleDialog.show(context,
            drawStatus: const SangongDrawStatus(roundId: 18));
      }
      await tester.pumpAndSettle();
      expect(
          sheet == 'preview'
              ? find.byType(SangongBetPreviewSheet)
              : find.byType(SangongRoundSettleDialog),
          findsOneWidget);
      api.privilege.setAllowed(false);
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(find.byType(SangongBetPreviewSheet, skipOffstage: false),
          findsNothing);
      expect(find.byType(SangongRoundSettleDialog, skipOffstage: false),
          findsNothing);
      expect(find.text('普通聊天'), findsOneWidget);
      expect(api.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
