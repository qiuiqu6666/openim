import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

import 'wallet_home_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('tokens show quantity left and raw value right in $brightness',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final controller = await loadedHomeController();
        await pumpWalletHome(tester,
            controller: controller, brightness: brightness);
        await tester.pumpAndSettle();
        expect(find.text('代币'), findsOneWidget);
        final toggle =
            tester.widget<IconButton>(walletHomeKey('wallet-assets-toggle'));
        expect(toggle.isSelected, isTrue);
        expect(toggle.tooltip, '收起代币');
        final filter =
            tester.widget<IconButton>(walletHomeKey('wallet-assets-filter'));
        expect(filter.isSelected, isFalse);
        expect(filter.tooltip, '按价值排序');
        for (final (key, label) in [
          ('wallet-assets-column-name', '名称/数量'),
          ('wallet-assets-column-value', '价值/现货收益'),
        ]) {
          final header = walletHomeKey(key);
          expect(tester.widget<Text>(header).data, label);
          final data = tester.getSemantics(header).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isFalse);
          expect(data.flagsCollection.isButton, isFalse);
        }
        for (final coin in walletHomeFixture.coins) {
          final quantity = walletHomeKey('wallet-asset-quantity-${coin.code}');
          final value = walletHomeKey('wallet-asset-value-${coin.code}');
          expect(find.text(coin.name), findsOneWidget);
          expect(tester.widget<Text>(quantity).data, coin.bal);
          expect(tester.widget<Text>(value).data, coin.fiat);
          expect(tester.getRect(quantity).left,
              lessThan(tester.getRect(value).left));
          expect(find.text(coin.sub), findsNothing,
              reason: 'The token list shows holdings rather than unit prices.');
        }
        final list = walletHomeKey('wallet-assets-list');
        expect(
            find.descendant(
                of: list,
                matching: find.textContaining(RegExp(r'APY|\d+(?:\.\d+)?%'))),
            findsNothing,
            reason:
                'No annualized earnings data exists in the wallet contract.');
        final dividers =
            find.descendant(of: list, matching: find.byType(Divider));
        expect(dividers, findsNWidgets(walletHomeFixture.coins.length - 1),
            reason: 'Only adjacent token rows have a divider.');
        for (final divider in tester.widgetList<Divider>(dividers)) {
          expect(divider.height, 1);
          expect(divider.thickness, 1);
        }
        expect(find.descendant(of: list, matching: find.byType(Card)),
            findsNothing);
        expect(
            find.descendant(
                of: list, matching: find.byIcon(Icons.chevron_right_rounded)),
            findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('collapsing tokens preserves hidden balances in $brightness',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repository = HomeTestRepository();
        final controller = await loadedHomeController(repository: repository);
        await pumpWalletHome(tester,
            controller: controller, brightness: brightness);
        await tester.pumpAndSettle();
        await _toggleBalances(tester);
        _expectHiddenTokenAmounts(tester);
        await _toggleList(tester);
        expect(walletHomeKey('wallet-assets-list'), findsNothing);
        expect(walletHomeKey('wallet-assets-column-name'), findsNothing);
        expect(walletHomeKey('wallet-assets-column-value'), findsNothing);
        final collapsed =
            tester.widget<IconButton>(walletHomeKey('wallet-assets-toggle'));
        expect(collapsed.isSelected, isFalse);
        expect(collapsed.tooltip, '展开代币');
        expect(controller.showBal, isFalse);

        await _toggleList(tester);
        expect(walletHomeKey('wallet-assets-list'), findsOneWidget);
        _expectHiddenTokenAmounts(tester);
        final spoken = tester
            .getSemantics(walletHomeKey('wallet-home-scroll'))
            .toStringDeep();
        for (final amount in [
          '8,652.48',
          '5,800.00',
          '402.325811',
          '2,852.48'
        ]) {
          expect(find.textContaining(amount), findsNothing);
          expect(spoken, isNot(contains(amount)));
        }
        await _toggleBalances(tester);
        for (final coin in walletHomeFixture.coins) {
          expect(
              tester
                  .widget<Text>(
                      walletHomeKey('wallet-asset-quantity-${coin.code}'))
                  .data,
              coin.bal);
          expect(
              tester
                  .widget<Text>(
                      walletHomeKey('wallet-asset-value-${coin.code}'))
                  .data,
              coin.fiat);
        }
        expect(repository.walletCalls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('value sorting survives collapse in $brightness',
        (tester) async {
      final repository = HomeTestRepository(data: walletHomeFilterFixture);
      final controller = await loadedHomeController(repository: repository);
      await pumpWalletHome(tester,
          controller: controller, brightness: brightness);
      await tester.pumpAndSettle();
      await tester.ensureVisible(walletHomeKey('wallet-assets-filter'));
      await tester.tap(walletHomeKey('wallet-assets-filter'));
      await tester.pumpAndSettle();
      expect(find.text('Small asset'), findsOneWidget);
      expect(find.text('Unknown valuation'), findsOneWidget);
      await _toggleList(tester);
      expect(walletHomeKey('wallet-assets-list'), findsNothing);
      expect(
          tester
              .widget<IconButton>(walletHomeKey('wallet-assets-filter'))
              .isSelected,
          isTrue);
      await _toggleList(tester);
      expect(find.text('Small asset'), findsOneWidget);
      expect(find.text('Known holding'), findsOneWidget);
      expect(find.text('Unknown valuation'), findsOneWidget);
      expect(
          tester.widget<Text>(walletHomeKey('wallet-asset-value-UNKNOWN')).data,
          '0.00');
      await tester.tap(walletHomeKey('wallet-assets-filter'));
      await tester.pumpAndSettle();
      expect(find.text('Small asset'), findsOneWidget);
      expect(repository.walletCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('blank and unknown valuations remain unknown without a prefix',
      (tester) async {
    const data = WalletDto(totalBal: '--', trxAddr: '', coins: [
      CoinDto(
          name: 'Unknown asset',
          code: 'UNKNOWN',
          sub: '¥123.45',
          bal: '--',
          fiat: '',
          type: CoinType.trx),
      CoinDto(
          name: 'Unpriced holding',
          code: 'UNPRICED',
          sub: '',
          bal: '3.250001',
          fiat: '--',
          type: CoinType.usdt),
    ]);
    final controller =
        await loadedHomeController(repository: HomeTestRepository(data: data));
    await pumpWalletHome(tester, controller: controller);
    await tester.pumpAndSettle();
    for (final code in ['UNKNOWN', 'UNPRICED']) {
      expect(
          tester.widget<Text>(walletHomeKey('wallet-asset-value-$code')).data,
          '--');
    }
    expect(
        tester
            .widget<Text>(walletHomeKey('wallet-asset-quantity-UNKNOWN'))
            .data,
        '--');
    expect(
        tester
            .widget<Text>(walletHomeKey('wallet-asset-quantity-UNPRICED'))
            .data,
        '3.250001');
    expect(find.text('¥123.45'), findsNothing);
    expect(find.text('≈ --'), findsNothing);
    expect(find.text('¥0.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _toggleList(WidgetTester tester) async {
  await tester.ensureVisible(walletHomeKey('wallet-assets-toggle'));
  await tester.tap(walletHomeKey('wallet-assets-toggle'));
  await tester.pumpAndSettle();
}

Future<void> _toggleBalances(WidgetTester tester) async {
  await tester.ensureVisible(walletHomeKey('wallet-toggle-balance'));
  await tester.tap(walletHomeKey('wallet-toggle-balance'));
  await tester.pumpAndSettle();
}

void _expectHiddenTokenAmounts(WidgetTester tester) {
  for (final code in ['99', 'USDT']) {
    for (final field in ['quantity', 'value']) {
      expect(
          tester.widget<Text>(walletHomeKey('wallet-asset-$field-$code')).data,
          '******');
    }
  }
}

