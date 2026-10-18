import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart'
    show SangongPageRoute;
import 'package:openim/pages/group_features/sangong/widgets/sangong_bet_preview_sheet.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_round_settle_dialog.dart';

import 'route_revalidation_fixture.dart';

final _pages = <String, Type>{
  'rules': SangongGameRulesSettingsPage,
  'manage': SangongManageHomePage,
  'cutoff': SangongBetPreviewSheet,
  'settle': SangongRoundSettleDialog,
};

void main() {
  testWidgets('settlement draft survives failed refresh and explicit retry',
      (tester) async {
    final fixture = RouteRevalidationFixture();
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'settle');
    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();
    final page = find.byType(SangongRoundSettleDialog);
    final element = tester.element(page);
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    final pending = fixture.capabilityRead!;
    fixture.capabilityRead = null;
    pending.completeError(StateError('offline'));
    await RouteRevalidationFixture.flush(tester);
    expect(tester.element(page), same(element));
    expect(find.text('暂时无法确认当前群权限，点击重试'), findsOneWidget);
    await tester.tap(find.text('暂时无法确认当前群权限，点击重试'));
    await RouteRevalidationFixture.flush(tester);
    expect(tester.element(page), same(element));
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.controller!.text),
        contains('7'));
    fixture.expectNoCommands();
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    fixture.canManage = false;
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(page, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'settlement keeps draft and geometry while refreshing dark=$dark',
        (tester) async {
      final fixture = RouteRevalidationFixture();
      await fixture.pumpChat(tester, dark: dark);
      await fixture.open(tester, 'settle');
      await tester.tap(find.text('7'));
      await tester.pumpAndSettle();
      final page = find.byType(SangongRoundSettleDialog);
      final element = tester.element(page);
      final bounds = tester.getRect(page);
      final fields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      final draft = fields.map((field) => field.controller!.text).toList();
      expect(draft, contains('7'));
      fixture.invalidate();
      await RouteRevalidationFixture.flush(tester);
      expect(tester.element(page), same(element));
      expect(tester.getRect(page), bounds);
      await tester.tap(find.text('8'), warnIfMissed: false);
      await tester.pump();
      expect(fields.map((field) => field.controller!.text).toList(), draft);
      fixture.expectNoCommands();
      fixture.resolveCapabilities();
      await RouteRevalidationFixture.flush(tester);
      expect(tester.element(page), same(element));
      expect(fields.map((field) => field.controller!.text).toList(), draft);
      await tester.tap(find.text('8'));
      await tester.pumpAndSettle();
      expect(fields.map((field) => field.controller!.text), contains('78'));
      expect(tester.takeException(), isNull);
    });
  }
  for (final entry in _pages.keys) {
    for (final dark in [false, true]) {
      testWidgets(
          '$entry remains open through capability and binding refresh, dark=$dark',
          (tester) async {
        final fixture = RouteRevalidationFixture();
        await fixture.pumpChat(tester, dark: dark);
        await fixture.open(tester, entry);
        final page = find.byType(_pages[entry]!);
        expect(page, findsOneWidget);
        final previousElement = tester.element(page);
        final navigator = fixture.navigator(tester);
        fixture.invalidate();
        await RouteRevalidationFixture.flush(tester);
        expect(navigator.canPop(), isTrue);
        expect(page, entry == 'settle' ? findsOneWidget : findsNothing);
        fixture.configRead = Completer<dynamic>();
        fixture.resolveCapabilities();
        await RouteRevalidationFixture.flush(tester);
        expect(navigator.canPop(), isTrue);
        expect(page, entry == 'settle' ? findsOneWidget : findsNothing);
        fixture.resolveConfig();
        await RouteRevalidationFixture.flush(tester);
        expect(page, findsOneWidget);
        expect(identical(tester.element(page), previousElement),
            entry == 'settle');
        expect(navigator.canPop(), isTrue);
        expect(find.text('正在确认当前群的三公配置'), findsNothing);
        fixture.expectNoCommands();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('temporary network failure retries on the same route',
      (tester) async {
    final fixture = RouteRevalidationFixture();
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'rules');
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
    expect(find.byType(SangongGameRulesSettingsPage), findsOneWidget);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });

  for (final change in ['denied', 'tenant', 'account', 'left']) {
    testWidgets('confirmed $change removes only the protected route',
        (tester) async {
      final fixture = RouteRevalidationFixture();
      await fixture.pumpChat(tester);
      await fixture.open(tester, 'rules');
      final navigator = fixture.navigator(tester);
      unawaited(navigator.push<void>(MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('普通资料')))));
      await tester.pumpAndSettle();
      fixture.invalidate();
      await RouteRevalidationFixture.flush(tester);
      switch (change) {
        case 'denied':
          fixture.canManage = false;
        case 'tenant':
          fixture.tenantID = 'other-tenant';
        case 'account':
          fixture.api.privilege.setAllowed(false);
        case 'left':
          fixture.active = false;
      }
      fixture.resolveCapabilities();
      await RouteRevalidationFixture.flush(tester);
      expect(find.text('普通资料'), findsOneWidget);
      expect(find.byType(SangongGameRulesSettingsPage, skipOffstage: false),
          findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(navigator.canPop(), isFalse);
      fixture.expectNoCommands();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('back during revalidation ignores the late response',
      (tester) async {
    final fixture = RouteRevalidationFixture();
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'rules');
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    fixture.navigator(tester).pop();
    await RouteRevalidationFixture.flush(tester);
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(fixture.navigator(tester).canPop(), isFalse);
    expect(find.byType(SangongGameRulesSettingsPage), findsNothing);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });

  testWidgets('another invalidation during binding uses the newest snapshot',
      (tester) async {
    final fixture = RouteRevalidationFixture();
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'rules');
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    fixture.configRead = Completer<dynamic>();
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    expect(fixture.navigator(tester).canPop(), isTrue);
    fixture.resolveConfig();
    await RouteRevalidationFixture.flush(tester);
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(find.byType(SangongGameRulesSettingsPage), findsOneWidget);
    expect(
        fixture.runtime.featureContext.capabilities.version, fixture.version);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested operator pages survive one shared revalidation',
      (tester) async {
    final fixture = RouteRevalidationFixture();
    await fixture.pumpChat(tester);
    await fixture.open(tester, 'rules');
    final navigator = fixture.navigator(tester);
    unawaited(navigator.push<void>(SangongPageRoute(
      context: tester.element(find.byType(SangongGameRulesSettingsPage)),
      builder: (_) => const Scaffold(body: Text('三公子页面')),
    )));
    await tester.pumpAndSettle();
    fixture.invalidate();
    await RouteRevalidationFixture.flush(tester);
    final readCount = fixture.api.count('/feature-capabilities');
    fixture.resolveCapabilities();
    await RouteRevalidationFixture.flush(tester);
    expect(find.text('三公子页面'), findsOneWidget);
    expect(fixture.api.count('/feature-capabilities'), readCount);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SangongGameRulesSettingsPage), findsOneWidget);
    fixture.expectNoCommands();
    expect(tester.takeException(), isNull);
  });

  for (final entry in ['cutoff', 'settle']) {
    testWidgets('$entry never reuses a form for a different round',
        (tester) async {
      final fixture = RouteRevalidationFixture();
      await fixture.pumpChat(tester);
      await fixture.open(tester, entry);
      fixture.invalidate();
      await RouteRevalidationFixture.flush(tester);
      fixture.roundID++;
      fixture.resolveCapabilities();
      await RouteRevalidationFixture.flush(tester);
      expect(fixture.navigator(tester).canPop(), isFalse);
      expect(find.byType(_pages[entry]!), findsNothing);
      fixture.expectNoCommands();
      expect(tester.takeException(), isNull);
    });
  }
}
