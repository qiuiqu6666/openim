import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/withdraw_transfer_confirm_screen.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

import '../../data/wallet_fund_test_api.dart';
import '../../operations/support/wallet_operation_test_support.dart';

void main() {
  for (final currency in [FundCurrency.usdt, FundCurrency.trx]) {
    testWidgets(
        '${currency.code} keypad displays exact rules and fee-adjusted maximum',
        (tester) async {
      final api = WalletTestFundApi(address: _address(currency));
      await _pump(tester, currency, api);
      expect(_text(tester, 'minimum'), '最低提现：10.000001 ${currency.code}');
      expect(_text(tester, 'fee'), '手续费：0.000001 ${currency.code}');
      await _type(tester, '10');
      expect(_next(tester).onPressed, isNotNull);
      expect(_text(tester, 'issue'), contains('10.000001'));
      await _type(tester, '.000001');
      expect(_next(tester).onPressed, isNotNull);
      expect(_text(tester, 'total'), '总扣款：10.000002 ${currency.code}');
      await tester.ensureVisible(find.text('100%'));
      await tester.tap(find.text('100%'));
      await tester.pump();
      expect(_text(tester, 'total'), '总扣款：100 ${currency.code}');
      expect(_next(tester).onPressed, isNotNull);
      expect(api.addressCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'principal equal to available balance shows the additional fee warning',
      (tester) async {
    final api = WalletTestFundApi(address: _address(FundCurrency.usdt));
    await _pump(tester, FundCurrency.usdt, api);
    await _type(tester, '100');
    expect(_next(tester).onPressed, isNotNull);
    expect(_text(tester, 'issue'), contains('提现金额和手续费'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'missing policy permits review recovery and manual retry uses server response',
      (tester) async {
    final api =
        WalletTestFundApi(address: depositAddressFixture(withRules: false));
    await _pump(tester, FundCurrency.usdt, api);
    await _type(tester, '10');
    expect(_next(tester).onPressed, isNotNull);
    expect(find.textContaining('提现规则暂不可用'), findsOneWidget);
    api.address = _address(FundCurrency.usdt);
    await tester.ensureVisible(
        find.byKey(const ValueKey('wallet-withdraw-entry-rules-retry')));
    await tester
        .tap(find.byKey(const ValueKey('wallet-withdraw-entry-rules-retry')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'fee'), '手续费：0.000001 USDT');
    await _type(tester, '.000001');
    expect(_next(tester).onPressed, isNotNull);
    expect(api.addressCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('friend entry performs no chain-rule request', (tester) async {
    final api = WalletTestFundApi();
    await _pump(tester, FundCurrency.usdt, api,
        mode: WithdrawTransferMode.friend);
    await _type(tester, '1');
    expect(_next(tester).onPressed, isNotNull);
    expect(api.addressCalls, 0);
    expect(find.byKey(const ValueKey('wallet-withdraw-entry-rules')),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      '100 percent remains exact when multiplying native integers would overflow',
      (tester) async {
    await _pump(tester, FundCurrency.usdt,
        WalletTestFundApi(address: _address(FundCurrency.usdt)),
        balanceMinor: 100000000000000001);
    await tester.tap(find.text('100%'));
    await tester.pump();
    expect(_text(tester, 'total'), '总扣款：100000000000.000001 USDT');
    expect(_next(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets('large text ${brightness.name} keeps chain rules scrollable',
        (tester) async {
      await _pump(tester, FundCurrency.trx,
          WalletTestFundApi(address: _address(FundCurrency.trx)),
          brightness: brightness, size: const Size(320, 844), textScale: 2);
      await _type(tester, '12');
      await tester.ensureVisible(
          find.byKey(const ValueKey('wallet-withdraw-entry-total')));
      await tester.pump();
      expect(_text(tester, 'total'), '总扣款：12.000001 TRX');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

WalletDepositAddress _address(FundCurrency currency) => WalletDepositAddress(
      status: 'ready',
      network: 'TRON',
      address: testDepositAddress,
      currencies: [currency],
      confirmations: 19,
      usdtContract: testUsdtContract,
      currencyRules: {
        currency: WalletCurrencyRule(
            currency: currency,
            minWithdrawAmount: '10.000001',
            withdrawFee: '0.000001',
            withdrawFeeCurrency: currency)
      },
    );

Future<void> _pump(
        WidgetTester tester, FundCurrency currency, WalletTestFundApi api,
        {WithdrawTransferMode mode = WithdrawTransferMode.chain,
        Brightness brightness = Brightness.light,
        Size size = const Size(390, 844),
        double textScale = 1,
        int? balanceMinor}) =>
    pumpWalletOperation(
        tester,
        WithdrawTransferConfirmScreen(
            mode: mode,
            coin: withdrawalTestCoin(currency),
            payMethod: balanceMinor == null
                ? withdrawalTestMethod(currency)
                : WalletPayMethodDto(
                    id: currency.code,
                    coin: currency.code,
                    code: currency.code,
                    net: 'TRON',
                    bal: '100000000000.000001',
                    fiat: '--',
                    balMinor: balanceMinor,
                    scale: currency.decimals,
                    color: Colors.blue,
                    badgeColor: Colors.blue,
                    badge: 'TRON'),
            targetValue: mode == WithdrawTransferMode.friend
                ? 'fixture-friend'
                : testDepositAddress,
            api: api,
            accountProvider: () => 'test-owner'),
        brightness: brightness,
        size: size,
        textScale: textScale);

Future<void> _type(WidgetTester tester, String input) async {
  for (final value in input.split('')) {
    await tester.tap(find.text(value).last);
    await tester.pump();
  }
}

ElevatedButton _next(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton));

String? _text(WidgetTester tester, String part) => tester
    .widget<Text>(find.byKey(ValueKey('wallet-withdraw-entry-$part')))
    .data;
