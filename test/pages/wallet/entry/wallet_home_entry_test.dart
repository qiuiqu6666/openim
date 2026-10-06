import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/trade_password_page.dart';
import 'package:openim/pages/wallet/entry/wallet_entry_coordinator.dart';

import 'support/wallet_entry_fixture.dart';
import 'support/wallet_entry_home_fixture.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  // The real profile intentionally keeps its decorative animations running.
  // Advance finite route transitions without waiting for those to stop.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('bottom wallet tab waits for real setup ($dark)',
        (tester) async {
      final settings = WalletEntrySettings()..ready = false;
      final coordinator = WalletEntryCoordinator(
          settingsFactory: () => settings, sessionKey: () => 'viewer');
      await mountWalletEntryHome(tester, coordinator: coordinator, dark: dark);
      expect(selectedWalletEntryTab(tester), 0);
      await tester.tap(walletEntryTab('钱包'));
      await _pumpHome(tester);
      expect(find.byType(TradePasswordPage), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      await enterPaymentPin(tester);
      await enterPaymentPin(tester);
      expect(find.byType(TradePasswordPage), findsNothing);
      expect(selectedWalletEntryTab(tester), 3);
      expect(settings.events, ['check', 'save', 'check']);
      await dismissEntryTip(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpHome(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profile wallet uses the same check and cancel keeps profile',
      (tester) async {
    final settings = WalletEntrySettings()..ready = false;
    final coordinator = WalletEntryCoordinator(
        settingsFactory: () => settings, sessionKey: () => 'viewer');
    await mountWalletEntryHome(tester, coordinator: coordinator);
    await tester.tap(walletEntryTab('我的'));
    await _pumpHome(tester);
    expect(selectedWalletEntryTab(tester), 4);
    await tester.ensureVisible(find.text('数字资产'));
    await tester.tap(find.text('数字资产'));
    await _pumpHome(tester);
    expect(find.byType(TradePasswordPage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await _pumpHome(tester);
    expect(selectedWalletEntryTab(tester), 4);
    expect(settings.checks, 1);
    settings.ready = true;
    await tester.ensureVisible(find.text('数字资产'));
    await tester.tap(find.text('数字资产'));
    await _pumpHome(tester);
    expect(selectedWalletEntryTab(tester), 3);
    expect(settings.checks, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpHome(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting another home tab cancels a pending wallet check',
      (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final coordinator = WalletEntryCoordinator(
        settingsFactory: () => settings, sessionKey: () => 'viewer');
    await mountWalletEntryHome(tester, coordinator: coordinator);
    await tester.tap(walletEntryTab('钱包'));
    await tester.pump();
    expect(selectedWalletEntryTab(tester), 0);
    await tester.tap(walletEntryTab('我的'));
    await _pumpHome(tester);
    expect(selectedWalletEntryTab(tester), 4);
    status.complete(false);
    await _pumpHome(tester);
    expect(find.byType(TradePasswordPage), findsNothing);
    expect(selectedWalletEntryTab(tester), 4);
    expect(settings.checks, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpHome(tester);
    expect(tester.takeException(), isNull);
  });
}
