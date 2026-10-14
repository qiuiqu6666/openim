import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/home/wallet_home_tokens.dart';

import 'wallet_home_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('trend expands without inventing history in $brightness',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repository = HomeTestRepository();
        final controller = await loadedHomeController(repository: repository);
        await pumpWalletHome(tester,
            controller: controller, brightness: brightness);
        await tester.pumpAndSettle();
        var button =
            tester.widget<IconButton>(walletHomeKey('wallet-action-overview'));
        expect(button.isSelected, isFalse);
        expect(button.tooltip, '展开资产趋势');
        expect(walletHomeKey('wallet-trend-panel'), findsNothing);

        await _toggleTrend(tester);
        button =
            tester.widget<IconButton>(walletHomeKey('wallet-action-overview'));
        expect(button.isSelected, isTrue);
        expect(button.tooltip, '收起资产趋势');
        final toggle = walletHomeKey('wallet-action-overview');
        final iconColor =
            button.style?.foregroundColor?.resolve({WidgetState.selected});
        expect(iconColor, WalletHomeTokens.trendIcon(tester.element(toggle)));
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
        expect(find.text('资产趋势'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-empty'), findsOneWidget);
        expect(find.text('暂无资产趋势数据'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-chart'), findsNothing);
        expect(walletHomeKey('wallet-trend-hidden'), findsNothing);
        _expectNoHistoryAmounts(tester);
        expect(repository.walletCalls, 1);

        await _toggleTrend(tester);
        expect(walletHomeKey('wallet-trend-panel'), findsNothing);
        expect(
            tester
                .widget<IconButton>(walletHomeKey('wallet-action-overview'))
                .isSelected,
            isFalse);
        expect(repository.walletCalls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
        'trend preserves privacy across collapse and refresh in $brightness',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repository = HomeTestRepository();
        final controller = await loadedHomeController(repository: repository);
        await pumpWalletHome(tester,
            controller: controller, brightness: brightness);
        await tester.pumpAndSettle();
        await _toggleTrend(tester);
        expect(find.text('¥8,652.48'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);

        await tester.ensureVisible(walletHomeKey('wallet-toggle-balance'));
        await tester.tap(walletHomeKey('wallet-toggle-balance'));
        await tester.pumpAndSettle();
        expect(walletHomeKey('wallet-trend-hidden'), findsOneWidget);
        expect(find.text('资产已隐藏'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-empty'), findsNothing);
        expect(walletHomeKey('wallet-trend-baseline'), findsNothing);
        _expectNoHistoryAmounts(tester);
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-hidden'), findsOneWidget);
        expect(find.textContaining('8,652.48'), findsNothing);
        expect(find.textContaining('1,220.16'), findsNothing);

        await tester.ensureVisible(walletHomeKey('wallet-toggle-balance'));
        await tester.tap(walletHomeKey('wallet-toggle-balance'));
        await tester.pumpAndSettle();
        expect(walletHomeKey('wallet-trend-empty'), findsOneWidget);
        await _toggleTrend(tester);
        await _toggleTrend(tester);
        expect(repository.walletCalls, 1,
            reason: 'Local visibility must not reload wallet data.');

        repository.respond = () async => walletHomeFilterFixture;
        await controller.load(force: true);
        await tester.pumpAndSettle();
        expect(find.text('¥10.10'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
        expect(walletHomeKey('wallet-display-currency'), findsOneWidget);
        expect(repository.walletCalls, 2);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    for (final textScale in [2.0, 3.0]) {
      testWidgets(
          'expanded trend fits 320px at ${textScale * 100}% in $brightness',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final repository = HomeTestRepository(data: walletHomeLongFixture);
          final controller = await loadedHomeController(repository: repository);
          await pumpWalletHome(tester,
              controller: controller,
              size: const Size(320, 844),
              brightness: brightness,
              textScale: textScale);
          await tester.pumpAndSettle();
          await _toggleTrend(tester);
          _expectActionsBelowPanel(tester);
          expect(walletHomeKey('wallet-trend-empty'), findsOneWidget);
          expect(walletHomeKey('wallet-trend-chart'), findsNothing);
          await tester.ensureVisible(walletHomeKey('wallet-trend-empty'));
          await tester.pumpAndSettle();
          final panel = tester.getRect(walletHomeKey('wallet-trend-panel'));
          expect(panel.left, greaterThanOrEqualTo(0));
          expect(panel.right, lessThanOrEqualTo(320));
          expect(repository.walletCalls, 1);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}

Future<void> _toggleTrend(WidgetTester tester) async {
  await tester.ensureVisible(walletHomeKey('wallet-action-overview'));
  await tester.tap(walletHomeKey('wallet-action-overview'));
  await tester.pumpAndSettle();
}

void _expectNoHistoryAmounts(WidgetTester tester) {
  final plotMessage = walletHomeKey('wallet-trend-hidden').evaluate().isNotEmpty
      ? walletHomeKey('wallet-trend-hidden')
      : walletHomeKey('wallet-trend-empty');
  final spoken = tester.getSemantics(plotMessage).toStringDeep();
  for (final amount in ['8,652.48', '1,220.16']) {
    expect(
        find.descendant(
            of: walletHomeKey('wallet-trend-panel'),
            matching: find.textContaining(amount)),
        findsNothing);
    expect(spoken, isNot(contains(amount)),
        reason: 'A current balance must not become a historical point.');
  }
}

void _expectActionsBelowPanel(WidgetTester tester) {
  final panel = tester.getRect(walletHomeKey('wallet-trend-panel'));
  final receive = tester.getRect(walletHomeKey('wallet-action-receive'));
  for (final action in ['receive', 'transfer', 'swap']) {
    final rect = tester.getRect(walletHomeKey('wallet-action-$action'));
    expect(rect.top, greaterThanOrEqualTo(panel.bottom));
    expect(rect.width, closeTo(receive.width, .01));
    expect(rect.height, closeTo(receive.height, .01));
    expect(rect.top, closeTo(receive.top, .01));
    expect(rect.height, greaterThanOrEqualTo(48));
  }
}
