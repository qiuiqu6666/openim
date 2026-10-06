import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';

import '../support/wallet_deposit_test_support.dart';

final _locales = <Locale,
    ({
  String wallet,
  String funding,
  String minutes,
  String seconds,
  String unlockUsdt,
  String unlockTrx,
  String noMemo,
  String requiredMemo,
})>{
  const Locale('zh', 'CN'): (
    wallet: '钱包账户',
    funding: '资金账户',
    minutes: '约2分钟',
    seconds: '约45秒',
    unlockUsdt: '64 次区块确认',
    unlockTrx: '80 次区块确认',
    noMemo: '无需备注',
    requiredMemo: '必须填写 Memo/Tag',
  ),
  const Locale('zh', 'TW'): (
    wallet: '錢包帳戶',
    funding: '資金帳戶',
    minutes: '約2分鐘',
    seconds: '約45秒',
    unlockUsdt: '64 次區塊確認',
    unlockTrx: '80 次區塊確認',
    noMemo: '無需備註',
    requiredMemo: '必須填寫 Memo/Tag',
  ),
  const Locale('en'): (
    wallet: 'Wallet account',
    funding: 'Funding account',
    minutes: 'About 2 min',
    seconds: 'About 45 sec',
    unlockUsdt: '64 block confirmations',
    unlockTrx: '80 block confirmations',
    noMemo: 'No memo is required.',
    requiredMemo: 'Memo/Tag is required',
  ),
  const Locale('ja'): (
    wallet: 'ウォレット口座',
    funding: '資金口座',
    minutes: '約2分',
    seconds: '約45秒',
    unlockUsdt: '64ブロックの承認',
    unlockTrx: '80ブロックの承認',
    noMemo: 'メモは不要です。',
    requiredMemo: 'Memo/Tag の入力が必要です',
  ),
  const Locale('ko'): (
    wallet: '지갑 계정',
    funding: '펀딩 계정',
    minutes: '약 2분',
    seconds: '약 45초',
    unlockUsdt: '64개 블록 확인',
    unlockTrx: '80개 블록 확인',
    noMemo: '메모는 필요하지 않습니다.',
    requiredMemo: 'Memo/Tag 입력이 필요합니다',
  ),
};

WalletDepositAddress _addressWithRules(
        Map<FundCurrency, WalletCurrencyRule> rules) =>
    WalletDepositAddress(
      status: 'ready',
      network: 'TRON',
      address: testDepositAddress,
      currencies: const [FundCurrency.usdt, FundCurrency.trx],
      confirmations: 19,
      usdtContract: testUsdtContract,
      currencyRules: rules,
    );

WalletDepositAddress _completeRulesAddress() => _addressWithRules({
      FundCurrency.usdt: WalletCurrencyRule(
        currency: FundCurrency.usdt,
        minDepositAmount: '1.000001',
        receivingAccountType: 'wallet',
        estimatedArrivalSeconds: 120,
        withdrawUnlockConfirmations: 64,
        memoRequired: false,
      ),
      FundCurrency.trx: WalletCurrencyRule(
        currency: FundCurrency.trx,
        minDepositAmount: '0.000001',
        receivingAccountType: 'funding',
        estimatedArrivalSeconds: 45,
        withdrawUnlockConfirmations: 80,
        memoRequired: true,
      ),
    });

void _expectRuleValue(String field, String value, {bool help = false}) {
  final prefix = help ? 'wallet-deposit-help' : 'wallet-deposit';
  expect(
      find.descendant(
          of: depositKey('$prefix-$field'), matching: find.text(value)),
      findsOneWidget);
}

void main() {
  for (final locale in _locales.entries) {
    for (final currency in [FundCurrency.usdt, FundCurrency.trx]) {
      testWidgets(
          '${locale.key} ${currency.code} renders its endpoint rule and exact minimum',
          (tester) async {
        final api = WalletTestFundApi(address: _completeRulesAddress());
        await pumpWalletDeposit(tester,
            api: api, locale: locale.key, currency: currency);
        final usdt = currency == FundCurrency.usdt;
        _expectRuleValue(
            'destination', usdt ? locale.value.wallet : locale.value.funding);
        _expectRuleValue('minimum', usdt ? '1.000001 USDT' : '0.000001 TRX');
        _expectRuleValue(
            'arrival-time', usdt ? locale.value.minutes : locale.value.seconds);
        _expectRuleValue('withdrawal-unlock',
            usdt ? locale.value.unlockUsdt : locale.value.unlockTrx);
        expect(
            find.descendant(
                of: depositKey('wallet-deposit-confirmations'),
                matching: find.textContaining('19')),
            findsOneWidget);
        expect(
            find.descendant(
                of: depositKey('wallet-deposit-notice'),
                matching: find.textContaining(
                    usdt ? locale.value.noMemo : locale.value.requiredMemo)),
            findsOneWidget);
        expect(tester.widget<Text>(depositKey('wallet-deposit-address')).data,
            testDepositAddress);
        expect(depositKey('wallet-deposit-contract-info'), findsNothing);
        expect(depositKey('wallet-deposit-contract-preview'), findsNothing);
        expect(api.addressCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('${locale.key} help uses the same selected currency rule',
        (tester) async {
      await pumpWalletDeposit(tester,
          api: WalletTestFundApi(address: _completeRulesAddress()),
          locale: locale.key,
          currency: FundCurrency.trx);
      await tester.tap(depositKey('wallet-deposit-network-info'));
      await tester.pumpAndSettle();
      expect(depositKey('wallet-deposit-help-sheet'), findsOneWidget);
      _expectRuleValue('destination', locale.value.funding, help: true);
      _expectRuleValue('minimum', '0.000001 TRX', help: true);
      _expectRuleValue('arrival-time', locale.value.seconds, help: true);
      _expectRuleValue('withdrawal-unlock', locale.value.unlockTrx, help: true);
      expect(
          find.descendant(
              of: depositKey('wallet-deposit-help-sheet'),
              matching: find.textContaining(locale.value.requiredMemo)),
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

  testWidgets('explicit zero rules remain zero rather than unknown',
      (tester) async {
    await pumpWalletDeposit(tester,
        api: WalletTestFundApi(
            address: _addressWithRules({
          FundCurrency.usdt: WalletCurrencyRule(
            currency: FundCurrency.usdt,
            receivingAccountType: 'spot',
            minDepositAmount: '0.000000',
            estimatedArrivalSeconds: 0,
            withdrawUnlockConfirmations: 0,
            memoRequired: false,
          ),
        })));
    _expectRuleValue('destination', '现货账户');
    _expectRuleValue('minimum', '0.000000 USDT');
    _expectRuleValue('arrival-time', '约0秒');
    _expectRuleValue('withdrawal-unlock', '0 次区块确认');
    expect(find.text('暂未提供'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'absent selected rules never borrow another currency or invent values',
      (tester) async {
    final usdtOnly = _addressWithRules({
      FundCurrency.usdt: _completeRulesAddress().ruleFor(FundCurrency.usdt)!,
    });
    await pumpWalletDeposit(tester,
        api: WalletTestFundApi(address: usdtOnly), currency: FundCurrency.trx);
    for (final field in [
      'destination',
      'minimum',
      'arrival-time',
      'withdrawal-unlock',
    ]) {
      _expectRuleValue(field, '暂未提供');
    }
    expect(find.text('1.000001 USDT'), findsNothing);
    expect(find.textContaining('要求未提供，请先确认'), findsOneWidget);
    expect(find.textContaining('无需备注'), findsNothing);
    expect(find.textContaining('必须填写'), findsNothing);
    await tester.tap(depositKey('wallet-deposit-network-info'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: depositKey('wallet-deposit-help-sheet'),
            matching: find.textContaining('要求未提供，请先确认')),
        findsOneWidget);
    expect(find.textContaining('无需备注'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown receiving account identifiers stay unknown',
      (tester) async {
    await pumpWalletDeposit(tester,
        api: WalletTestFundApi(
            address: _addressWithRules({
          FundCurrency.usdt: WalletCurrencyRule(
            currency: FundCurrency.usdt,
            receivingAccountType: 'new-server-account',
            memoRequired: false,
          ),
        })));
    _expectRuleValue('destination', '暂未提供');
    expect(find.text('new-server-account'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets('320px 2x ${brightness.name} rules and help remain scrollable',
        (tester) async {
      await pumpWalletDeposit(tester,
          api: WalletTestFundApi(address: _completeRulesAddress()),
          brightness: brightness,
          currency: FundCurrency.trx,
          size: const Size(320, 844),
          textScale: 2);
      expect(tester.takeException(), isNull);
      final pageScrollable = find
          .descendant(
              of: depositKey('wallet-deposit-scroll'),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
          depositKey('wallet-deposit-withdrawal-unlock'), 240,
          scrollable: pageScrollable);
      await tester.pumpAndSettle();
      _expectRuleValue('withdrawal-unlock', '80 次区块确认');
      final row =
          tester.getRect(depositKey('wallet-deposit-withdrawal-unlock'));
      expect(row.left, greaterThanOrEqualTo(0));
      expect(row.right, lessThanOrEqualTo(320));
      await tester.ensureVisible(depositKey('wallet-deposit-network-info'));
      await tester.tap(depositKey('wallet-deposit-network-info'));
      await tester.pumpAndSettle();
      final helpScrollable = find
          .descendant(
              of: depositKey('wallet-deposit-help-sheet'),
              matching: find.byType(Scrollable))
          .first;
      expect(
          tester
              .state<ScrollableState>(helpScrollable)
              .position
              .maxScrollExtent,
          greaterThan(0));
      await tester.scrollUntilVisible(
          depositKey('wallet-deposit-help-withdrawal-unlock'), 180,
          scrollable: helpScrollable);
      await tester.pumpAndSettle();
      _expectRuleValue('minimum', '0.000001 TRX', help: true);
      _expectRuleValue('withdrawal-unlock', '80 次区块确认', help: true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
