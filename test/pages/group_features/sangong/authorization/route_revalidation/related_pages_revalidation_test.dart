import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_all_users_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_members_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_my_config_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_team_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_transfers_page.dart';
import 'package:openim/pages/group_features/sangong/agents/pages/sangong_agent_groups_page.dart';
import 'package:openim/pages/group_features/sangong/report_center/pages/report_center_page.dart';
import 'package:openim/pages/group_features/sangong/report_center/pages/report_detail_page.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'route_revalidation_fixture.dart';

void main() {
  final pages = <Widget>[
    const SangongAllUsersPage(),
    const SangongMembersPage(),
    const SangongMyConfigPage(groupScoped: true),
    const SangongAgentGroupsPage(),
    const SangongReportCenterPage(),
    const SangongReportDetailPage(
        title: '报表详情', resource: 'management-summary', query: {}),
    SangongUserDetailPage(
        user: SangongAdminUserReport.fromJson(
            {'userId': 19, 'imUserId': 'owner'})),
    const SangongAgentTransfersPage(),
    SangongAgentMemberDetailPage(
        member: SangongTeamMemberDto.fromJson(
            {'imUserId': 'owner', 'nickname': '代理'})),
  ];
  for (final page in pages) {
    final agent = page is SangongAgentTransfersPage ||
        page is SangongAgentMemberDetailPage;
    for (final dark in [false, true]) {
      testWidgets(
          '${page.runtimeType} refresh keeps the nested route dark=$dark',
          (tester) async {
        final fixture = RouteRevalidationFixture(agent: agent);
        await fixture.pumpChat(tester, dark: dark);
        await fixture.open(tester, agent ? 'team' : 'manage');
        final context = tester.element(
            find.byType(agent ? SangongAgentTeamPage : SangongScope).last);
        unawaited(Navigator.of(context).push(SangongPageRoute<void>(
          context: context,
          agent: agent,
          configuration: page is SangongMyConfigPage,
          builder: (_) => page,
        )));
        await RouteRevalidationFixture.flush(tester);
        expect(find.byType(page.runtimeType), findsOneWidget);
        final before = tester.element(find.byType(page.runtimeType));
        fixture.invalidate();
        await RouteRevalidationFixture.flush(tester);
        expect(fixture.navigator(tester).canPop(), isTrue);
        fixture.resolveCapabilities();
        await RouteRevalidationFixture.flush(tester);
        expect(find.byType(page.runtimeType), findsOneWidget);
        expect(identical(before, tester.element(find.byType(page.runtimeType))),
            isFalse);
        expect(find.text('正在确认当前群的三公配置'), findsNothing);
        fixture.expectNoCommands();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'configuration-only access survives refresh without a management grant',
      (tester) async {
    final fixture = RouteRevalidationFixture()..canManage = false;
    await fixture.pumpChat(tester);
    final context =
        tester.element(find.byKey(RouteRevalidationFixture.chatKey));
    unawaited(SangongMyConfigPage.open(context, groupScoped: true));
    await RouteRevalidationFixture.flush(tester);
    expect(find.byType(SangongMyConfigPage), findsOneWidget);
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(find.byType(SangongMyConfigPage), findsOneWidget);
    expect(fixture.runtime.canManage, isFalse);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });

  for (final prompt in [false, true]) {
    testWidgets(
        'pure agent ${prompt ? 'prompt' : 'confirmation'} cancels only itself on refresh',
        (tester) async {
      final fixture = RouteRevalidationFixture(agent: true);
      await fixture.pumpChat(tester);
      await fixture.open(tester, 'team');
      final context = tester.element(find.byType(SangongAgentTeamPage));
      final Future<Object?> result = prompt
          ? AppDialog.prompt(context: context, title: '输入划转金额')
          : AppDialog.confirm(context: context, title: '确认划转', message: '待确认');
      await RouteRevalidationFixture.flush(tester);
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      fixture.invalidate();
      await RouteRevalidationFixture.flush(tester);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(await result, prompt ? isNull : isFalse);
      fixture.resolveCapabilities();
      await RouteRevalidationFixture.flush(tester);
      expect(find.byType(SangongAgentTeamPage), findsOneWidget);
      fixture.expectNoCommands();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'configuration revocation is not overridden by group admin status',
      (tester) async {
    final fixture = RouteRevalidationFixture()..canManage = false;
    await fixture.pumpChat(tester);
    unawaited(SangongMyConfigPage.open(
        tester.element(find.byKey(RouteRevalidationFixture.chatKey)),
        groupScoped: true));
    await RouteRevalidationFixture.flush(tester);
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    fixture.canConfigure = false;
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(find.byType(SangongMyConfigPage), findsNothing);
    expect(fixture.navigator(tester).canPop(), isFalse);
    fixture.expectNoCommands();
  });

  testWidgets('selection expires without closing the underlying business page',
      (tester) async {
    final fixture = RouteRevalidationFixture();
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'rules');
    final context = tester.element(find.byType(SangongScope).last);
    final result = Navigator.of(context).push(SangongPageRoute<Object>(
        context: context,
        recoverOnRefresh: false,
        builder: (_) => const Scaffold(body: Text('选择绑定群'))));
    await RouteRevalidationFixture.flush(tester);
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    expect(await result, isNull);
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(find.text('选择绑定群'), findsNothing);
    expect(fixture.navigator(tester).canPop(), isTrue);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });
}
