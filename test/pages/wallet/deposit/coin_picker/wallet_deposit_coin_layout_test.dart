import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wallet_deposit_coin_test_support.dart';

void main() {
  testWidgets('popular list has one row per coin without groups or an index',
      (tester) async {
    await pumpWalletDepositCoins(tester,
        api: WalletTestFundApi(), size: const Size(390, 350));
    expect(find.text('热门币种'), findsOneWidget);
    expect(coinRow('USDT'), findsOneWidget);
    expect(coinRow('TRX'), findsOneWidget);
    expect(find.text('USDT'), findsOneWidget);
    expect(find.text('TRX'), findsOneWidget);
    for (final code in ['USDT', 'TRX']) {
      expect(coinKey('wallet-deposit-coin-all-$code'), findsNothing);
    }
    for (final letter in ['T', 'U']) {
      expect(coinKey('wallet-deposit-coin-group-$letter'), findsNothing);
      expect(coinKey('wallet-deposit-coin-index-$letter'), findsNothing);
      expect(find.text(letter), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final translations = <Locale, (String, String, String)>{
    Locale('zh', 'CN'): ('选择币种', '热门币种', '未找到匹配币种'),
    Locale('zh', 'TW'): ('選擇幣種', '熱門幣種', '未找到符合的幣種'),
    Locale('en'): ('Select coin', 'Popular coins', 'No matching coins'),
    Locale('ja'): ('通貨を選択', '人気の通貨', '一致する通貨がありません'),
    Locale('ko'): ('코인 선택', '인기 코인', '일치하는 코인이 없습니다'),
  };
  for (final entry in translations.entries) {
    testWidgets('picker uses ${entry.key} for title, sections and empty state',
        (tester) async {
      await pumpWalletDepositCoins(tester,
          api: WalletTestFundApi(), locale: entry.key);
      expect(find.text(entry.value.$1), findsOneWidget);
      expect(find.text(entry.value.$2), findsOneWidget);
      await searchCoins(tester, 'unknown');
      expect(find.text(entry.value.$3), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final brightness in Brightness.values) {
    for (final locale in [const Locale('zh', 'CN'), const Locale('ja')]) {
      testWidgets(
          '320px 2x ${locale.languageCode} ${brightness.name} remains usable with keyboard',
          (tester) async {
        final api = WalletTestFundApi();
        await pumpWalletDepositCoins(tester,
            api: api,
            brightness: brightness,
            locale: locale,
            size: const Size(320, 844),
            textScale: 2);
        expect(tester.takeException(), isNull);
        expect(coinRow('USDT').hitTestable(), findsOneWidget);
        expect(
            tester.getSize(coinRow('USDT')).height, greaterThanOrEqualTo(48));
        await searchCoins(tester, 'trx');
        tester.view.viewInsets = const FakeViewPadding(bottom: 360);
        await tester.pumpAndSettle();
        final search = tester.getRect(coinKey('wallet-deposit-coin-search'));
        final cancel = tester.getRect(coinKey('wallet-deposit-coin-cancel'));
        final row = tester.getRect(coinRow('TRX', searching: true));
        for (final rect in [search, cancel, row]) {
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.bottom, lessThanOrEqualTo(844 - 360));
        }
        expect(coinRow('TRX', searching: true).hitTestable(), findsOneWidget);
        expect(coinKey('wallet-deposit-coin-cancel').hitTestable(),
            findsOneWidget);
        await tester.tap(coinKey('wallet-deposit-coin-cancel'));
        await tester.pump();
        expect(
            tester
                .widget<TextField>(coinKey('wallet-deposit-coin-search'))
                .focusNode!
                .hasFocus,
            isFalse);
        expect(tester.takeException(), isNull);
        expect(api.addressCalls, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
