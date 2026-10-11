import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_team_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_personal_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';

import 'route_revalidation_fixture.dart';

const pages = <String, Type>{
  'team': SangongAgentTeamPage,
  'dashboard': SangongAgentDashboardPage,
  'personal': SangongAgentPersonalPage,
};

void main() {
  testWidgets(
      'agent nested page keeps its shared hall runtime during revalidation',
      (tester) async {
    final fixture = RouteRevalidationFixture(agent: true);
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'team');
    final element = tester.element(find.byType(SangongAgentTeamPage));
    final runtime = SangongScope.read(element);
    unawaited(Navigator.of(element).push(SangongPageRoute<void>(
        context: element,
        agent: true,
        builder: (_) => const Scaffold(body: Text('下级详情')))));
    await RouteRevalidationFixture.flush(tester);
    expect(find.text('下级详情'), findsOneWidget);
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(find.text('下级详情'), findsOneWidget);
    final current = SangongScope.read(tester.element(find.text('下级详情')));
    expect(identical(current, runtime), isTrue);
    expect(current.canOpenAgent, isTrue);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });
  for (final entry in pages.keys) {
    for (final dark in [false, true]) {
      testWidgets(
          'assigned agent $entry stays on page after cache refresh dark=$dark',
          (tester) async {
        final fixture = RouteRevalidationFixture(agent: true);
        await fixture.pumpChat(tester, dark: dark);
        await fixture.open(tester, entry);
        expect(find.byType(pages[entry]!), findsOneWidget);
        final navigator = fixture.navigator(tester);
        fixture.invalidate();
        await RouteRevalidationFixture.flush(tester);
        expect(navigator.canPop(), isTrue);
        expect(find.byType(pages[entry]!), findsNothing);
        fixture.resolveCapabilities();
        await RouteRevalidationFixture.flush(tester);
        expect(navigator.canPop(), isTrue);
        expect(find.byType(pages[entry]!), findsOneWidget);
        expect(find.text('正在确认当前群的三公配置'), findsNothing);
        fixture.expectNoCommands();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('agent network error stays on same route and can retry',
      (tester) async {
    final fixture = RouteRevalidationFixture(agent: true);
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'team');
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    final pending = fixture.capabilityRead!;
    fixture.capabilityRead = null;
    pending.completeError(StateError('network unavailable'));
    await RouteRevalidationFixture.flush(tester);
    expect(fixture.navigator(tester).canPop(), isTrue);
    expect(find.text('暂时无法确认当前群权限，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await RouteRevalidationFixture.flush(tester);
    expect(find.byType(SangongAgentTeamPage), findsOneWidget);
    fixture.expectNoCommands();
  });

  testWidgets('logout during agent refresh cannot restore private content',
      (tester) async {
    final fixture = RouteRevalidationFixture(agent: true);
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'personal');
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    fixture.active = false;
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(find.byType(SangongAgentPersonalPage), findsNothing);
    expect(fixture.navigator(tester).canPop(), isFalse);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });

  for (final revoke in [true, false]) {
    testWidgets(
        'agent explicit ${revoke ? 'revocation' : 'hall change'} closes the private page',
        (tester) async {
      final fixture = RouteRevalidationFixture(agent: true);
      await fixture.pumpChat(tester);
      await fixture.open(tester, 'dashboard');
      fixture.invalidate();
      await RouteRevalidationFixture.flush(tester);
      if (revoke) {
        fixture.canOpenAgent = false;
      } else {
        fixture.tenantID = 'other-hall';
      }
      fixture.resolveCapabilities();
      await RouteRevalidationFixture.flush(tester);
      expect(find.byType(SangongAgentDashboardPage), findsNothing);
      expect(fixture.navigator(tester).canPop(), isFalse);
      fixture.expectNoCommands();
      expect(tester.takeException(), isNull);
    });
  }
}
