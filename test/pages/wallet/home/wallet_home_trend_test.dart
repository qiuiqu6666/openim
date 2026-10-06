import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/home/wallet_home_tokens.dart';

import 'wallet_home_test_support.dart';

const _days = [7, 30, 90, 180, 360];

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
        expect(walletHomeKey('wallet-trend-baseline'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-hidden'), findsNothing);
        _expectSelectedPeriod(tester, 7);
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
        'trend keeps period across currency, privacy and refresh in $brightness',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repository = HomeTestRepository();
        final controller = await loadedHomeController(repository: repository);
        await pumpWalletHome(tester,
            controller: controller, brightness: brightness);
        await tester.pumpAndSettle();
        await _toggleTrend(tester);
        await _selectPeriod(tester, 30);
        _expectSelectedPeriod(tester, 30);
        await _selectCurrency(tester, 'USD');
        expect(find.text(r'$1,220.16'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
        _expectSelectedPeriod(tester, 30);

        await tester.ensureVisible(walletHomeKey('wallet-toggle-balance'));
        await tester.tap(walletHomeKey('wallet-toggle-balance'));
        await tester.pumpAndSettle();
        expect(walletHomeKey('wallet-trend-hidden'), findsOneWidget);
        expect(find.text('资产已隐藏'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-empty'), findsNothing);
        expect(walletHomeKey('wallet-trend-baseline'), findsNothing);
        _expectNoHistoryAmounts(tester);
        await _selectCurrency(tester, 'CNY');
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-hidden'), findsOneWidget);
        expect(find.textContaining('8,652.48'), findsNothing);
        expect(find.textContaining('1,220.16'), findsNothing);

        await tester.ensureVisible(walletHomeKey('wallet-toggle-balance'));
        await tester.tap(walletHomeKey('wallet-toggle-balance'));
        await tester.pumpAndSettle();
        expect(walletHomeKey('wallet-trend-empty'), findsOneWidget);
        _expectSelectedPeriod(tester, 30);
        await _toggleTrend(tester);
        await _toggleTrend(tester);
        _expectSelectedPeriod(tester, 30);
        expect(repository.walletCalls, 1,
            reason:
                'Local periods and visibility must not reload wallet data.');

        await _selectCurrency(tester, 'USD');
        repository.respond = () async => walletHomeFilterFixture;
        await controller.load(force: true);
        await tester.pumpAndSettle();
        expect(find.text('¥10.10'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
        _expectSelectedPeriod(tester, 30);
        expect(
            find.descendant(
                of: walletHomeKey('wallet-display-currency'),
                matching: find.text('CNY')),
            findsOneWidget);
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
          for (final days in _days) {
            final rect =
                tester.getRect(walletHomeKey('wallet-trend-period-$days'));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          await tester.ensureVisible(walletHomeKey('wallet-trend-period-7'));
          await tester.pumpAndSettle();
          final horizontal = find.descendant(
              of: walletHomeKey('wallet-trend-panel'),
              matching: find.byWidgetPredicate((widget) =>
                  widget is Scrollable &&
                  (widget.axisDirection == AxisDirection.right ||
                      widget.axisDirection == AxisDirection.left)));
          expect(horizontal, findsOneWidget);
          await tester.drag(horizontal, const Offset(-650, 0));
          await tester.pumpAndSettle();
          expect(walletHomeKey('wallet-trend-period-360').hitTestable(),
              findsOneWidget);
          await tester.tap(walletHomeKey('wallet-trend-period-360'));
          await tester.pumpAndSettle();
          _expectSelectedPeriod(tester, 360);
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

Future<void> _selectPeriod(WidgetTester tester, int days) async {
  final period = walletHomeKey('wallet-trend-period-$days');
  await tester.ensureVisible(period);
  await tester.tap(period);
  await tester.pumpAndSettle();
}

Future<void> _selectCurrency(WidgetTester tester, String currency) async {
  await tester.ensureVisible(walletHomeKey('wallet-display-currency'));
  await tester.tap(walletHomeKey('wallet-display-currency'));
  await tester.pumpAndSettle();
  await tester.tap(find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String> && widget.value == currency));
  await tester.pumpAndSettle();
}

void _expectSelectedPeriod(WidgetTester tester, int selected) {
  for (final days in _days) {
    final selection = find
        .ancestor(
            of: walletHomeKey('wallet-trend-period-$days'),
            matching: find.byWidgetPredicate((widget) =>
                widget is Semantics && widget.properties.selected != null))
        .first;
    expect(tester.widget<Semantics>(selection).properties.selected,
        days == selected);
  }
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
