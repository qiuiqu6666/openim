import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/deposit/wallet_deposit_tokens.dart';
import 'package:openim/pages/wallet/deposit/widgets/wallet_deposit_address_card.dart';
import 'package:openim/pages/wallet/deposit/widgets/wallet_deposit_qr.dart';

import 'support/wallet_deposit_qr_expectation.dart';
import 'support/wallet_deposit_test_support.dart';

void main() {
  for (final currency in [FundCurrency.usdt, FundCurrency.trx]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'compact ${currency.code} QR is separate and decodable ${brightness.name}',
          (tester) async {
        final boundary = GlobalKey();
        await pumpWalletDeposit(tester,
            api: WalletTestFundApi(),
            boundaryKey: boundary,
            currency: currency,
            brightness: brightness);
        await tester.runAsync(() => precacheImage(
            const AssetImage('assets/img/TRX.png'),
            tester.element(depositKey('wallet-deposit-records'))));
        await tester.pumpAndSettle();
        expect(find.byType(WalletDepositQr), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(WalletDepositAddressCard),
                matching: find.byType(WalletDepositQr)),
            findsNothing);
        expect(tester.getSize(depositKey('wallet-deposit-qr')),
            const Size(WalletDepositTokens.qrSize, WalletDepositTokens.qrSize));
        expect(tester.getSize(depositKey('wallet-deposit-qr')).width,
            lessThanOrEqualTo(180));
        expect(
            tester.getRect(depositKey('wallet-deposit-qr')).bottom,
            lessThan(
                tester.getRect(find.byType(WalletDepositAddressCard)).top));
        expect(
            await decodeDepositRenderedQr(
                tester, boundary, depositKey('wallet-deposit-qr')),
            testDepositAddress);
        expect(tester.widget<Text>(depositKey('wallet-deposit-address')).data,
            testDepositAddress);
        expect(depositKey('wallet-deposit-address-copy'), findsOneWidget);
        expect(depositKey('wallet-deposit-copy'), findsNothing);
        expect(
            find.descendant(
                of: find.byType(AppBar),
                matching: find.textContaining(currency.code)),
            findsOneWidget);
        for (final key in ['wallet-deposit-help', 'wallet-deposit-records']) {
          expect(depositKey(key).hitTestable(), findsOneWidget);
          expect(
              tester.getSize(depositKey(key)).height, greaterThanOrEqualTo(48));
        }
        expect(
            depositKey('wallet-deposit-share').hitTestable(), findsOneWidget);
        expect(tester.getRect(depositKey('wallet-deposit-share')).bottom,
            lessThanOrEqualTo(844));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'unknown metadata stays unknown while confirmations use the endpoint',
      (tester) async {
    final api = WalletTestFundApi(
        address: WalletDepositAddress(
            status: 'ready',
            network: 'TRON',
            address: testDepositAddress,
            currencies: const [FundCurrency.usdt, FundCurrency.trx],
            confirmations: 7,
            usdtContract: testUsdtContract));
    await pumpWalletDeposit(tester, api: api);
    expect(find.text('暂未提供'), findsNWidgets(4));
    expect(find.textContaining('7 个区块'), findsOneWidget);
    for (final invented in ['0.1 USDT', '2分钟', '2 分钟', '33 个区块', '资金账户']) {
      expect(find.textContaining(invented), findsNothing);
    }
    expect(
        tester.widget<Text>(depositKey('wallet-deposit-network')).data, 'Tron');
    expect(find.text('Ethereum'), findsNothing);
    expect(find.text('BSC'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  const locales = [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('ja'),
    Locale('ko')
  ];
  for (final locale in locales) {
    testWidgets('ready address and help use ${locale.toLanguageTag()}',
        (tester) async {
      await pumpWalletDeposit(tester, api: WalletTestFundApi(), locale: locale);
      expect(
          find.descendant(
              of: find.byType(AppBar), matching: find.textContaining('USDT')),
          findsOneWidget);
      final title = switch (locale.languageCode) {
        'en' => 'Deposit information',
        'ja' => '入金について',
        'ko' => '입금 안내',
        _ => locale.countryCode == 'TW' ? '儲值須知' : '充值须知',
      };
      await tester.tap(depositKey('wallet-deposit-help'));
      await tester.pumpAndSettle();
      expect(depositKey('wallet-deposit-help-sheet'), findsOneWidget);
      expect(
          find.descendant(
              of: depositKey('wallet-deposit-help-sheet'),
              matching: find.text(title)),
          findsOneWidget);
      expect(
          find.descendant(
              of: depositKey('wallet-deposit-help-sheet'),
              matching: find.textContaining('19')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
