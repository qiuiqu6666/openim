import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wallet_withdraw_coin_test_support.dart';

void main() {
  testWidgets(
      'popular list shows each enabled coin once without alphabet groups',
      (tester) async {
    await pumpWalletWithdrawCoins(tester, size: const Size(390, 350));
    expect(find.text('热门币种'), findsOneWidget);
    for (final code in ['USDT', 'TRX', '99']) {
      expect(withdrawCoinRow(code), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(withdrawCoinKey('all-$code'), findsNothing);
    }
    for (final letter in ['9', 'T', 'U']) {
      expect(withdrawCoinKey('group-$letter'), findsNothing);
      expect(withdrawCoinKey('index-$letter'), findsNothing);
      expect(find.text(letter), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final translations = <Locale, (String, String, String)>{
    Locale('zh', 'CN'): ('选择币种', '热门币种', '未找到匹配币种'),
    Locale('zh', 'TW'): ('選擇幣種', '熱門幣種', '未找到符合的幣種'),
    Locale('en', 'US'): ('Select coin', 'Popular coins', 'No matching coins'),
    Locale('ja', 'JP'): ('通貨を選択', '人気の通貨', '一致する通貨がありません'),
    Locale('ko', 'KR'): ('코인 선택', '인기 코인', '일치하는 코인이 없습니다'),
  };
  for (final entry in translations.entries) {
    testWidgets('current ${entry.key} labels and empty state are localized',
        (tester) async {
      await pumpWalletWithdrawCoins(tester, locale: entry.key);
      expect(find.text(entry.value.$1), findsOneWidget);
      expect(find.text(entry.value.$2), findsOneWidget);
      await searchWithdrawCoins(tester, 'missing fixture currency');
      expect(find.text(entry.value.$3), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final brightness in Brightness.values) {
    for (final locale in [const Locale('zh', 'CN'), const Locale('ja', 'JP')]) {
      testWidgets(
          '320px 2x ${locale.languageCode} ${brightness.name} supports keyboard search and cancel',
          (tester) async {
        final repository = HomeTestRepository(data: withdrawWalletFixture());
        await pumpWalletWithdrawCoins(tester,
            repository: repository,
            brightness: brightness,
            locale: locale,
            size: const Size(320, 844),
            textScale: 2);
        expect(tester.takeException(), isNull);
        expect(withdrawCoinRow('USDT').hitTestable(), findsOneWidget);
        expect(tester.getSize(withdrawCoinRow('USDT')).height,
            greaterThanOrEqualTo(48));
        await searchWithdrawCoins(tester, 'trx');
        tester.view.viewInsets = const FakeViewPadding(bottom: 360);
        await tester.pumpAndSettle();
        for (final item in [
          withdrawCoinKey('search'),
          withdrawCoinKey('cancel'),
          withdrawCoinRow('TRX', section: 'search'),
        ]) {
          final rect = tester.getRect(item);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.bottom, lessThanOrEqualTo(844 - 360));
          expect(item.hitTestable(), findsOneWidget);
        }
        await tester.tap(withdrawCoinKey('cancel'));
        await tester.pump();
        final field = tester.widget<TextField>(withdrawCoinKey('search'));
        expect(field.controller!.text, isEmpty);
        expect(field.focusNode!.hasFocus, isFalse);
        expect(repository.walletCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
