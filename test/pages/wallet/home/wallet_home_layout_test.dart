import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_home_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final locale in walletHomeLocales) {
      testWidgets('small-screen layout handles $locale in $brightness',
          (tester) async {
        final controller = await loadedHomeController(
          repository: HomeTestRepository(data: walletHomeLongFixture),
        );
        for (final width in [320.0, 390.0]) {
          await pumpWalletHome(tester,
              controller: controller,
              size: Size(width, 844),
              brightness: brightness,
              locale: locale,
              textScale: 1.5);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$width px, $locale, $brightness, 150% text');
          _expectMatchingActionHeights(tester);
          for (final key in [
            'wallet-action-receive',
            'wallet-action-transfer',
            'wallet-action-swap',
            'wallet-action-record',
            'wallet-action-overview',
            'wallet-display-currency',
            'wallet-toggle-balance',
            'wallet-assets-filter',
            'wallet-assets-toggle',
          ]) {
            final rect = tester.getRect(walletHomeKey(key));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.height, greaterThanOrEqualTo(48), reason: key);
          }
          _expectCompleteTotal(tester, width);
          await tester
              .ensureVisible(find.text(walletHomeLongFixture.coins.first.name));
          await tester.pumpAndSettle();
          expect(
              find.textContaining('123,456,789,012,345.123456'), findsWidgets,
              reason: 'The amount string must retain its original precision');
          _expectCompleteAssetAmounts(tester, width);
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets(
        'wide layout retains reading order in a centered column in $brightness',
        (tester) async {
      final controller = await loadedHomeController();
      await pumpWalletHome(tester,
          controller: controller,
          size: const Size(900, 800),
          brightness: brightness);
      await tester.pumpAndSettle();
      final amount = tester.getRect(walletHomeKey('wallet-total-amount'));
      final swap = tester.getRect(walletHomeKey('wallet-action-swap'));
      final assets = tester.getRect(walletHomeKey('wallet-assets-section'));
      expect(swap.top, greaterThan(amount.bottom));
      expect(assets.top, greaterThan(swap.bottom));
      expect(assets.width, lessThanOrEqualTo(680));
      expect(assets.center.dx, closeTo(450, .01));
      _expectMatchingActionHeights(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long USD estimate keeps every digit in $brightness',
        (tester) async {
      final controller = await loadedHomeController(
          repository: HomeTestRepository(data: walletHomeLongFixture));
      await pumpWalletHome(tester,
          controller: controller,
          size: const Size(320, 844),
          brightness: brightness,
          textScale: 2);
      await tester.pumpAndSettle();
      await tester.tap(walletHomeKey('wallet-display-currency'));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((widget) =>
          widget is PopupMenuItem<String> && widget.value == 'USD'));
      await tester.pumpAndSettle();
      _expectCompleteTotal(tester, 320, currency: 'USD');
      _expectMatchingActionHeights(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('overview shows the requested estimate and three action labels',
      (tester) async {
    final controller = await loadedHomeController();
    await pumpWalletHome(tester, controller: controller);
    await tester.pumpAndSettle();
    expect(find.text('总资产估值'), findsOneWidget);
    for (final (key, label) in [
      ('wallet-action-receive', '充值'),
      ('wallet-action-transfer', '提现'),
      ('wallet-action-swap', '划转'),
    ]) {
      expect(
          find.descendant(of: walletHomeKey(key), matching: find.text(label)),
          findsOneWidget);
    }
    _expectMatchingActionHeights(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone home keeps actions above the bottom safe area',
      (tester) async {
    final controller = await loadedHomeController();
    await pumpWalletHome(tester,
        controller: controller,
        size: const Size(390, 844),
        safePadding: const EdgeInsets.only(top: 44, bottom: 34));
    await tester.pumpAndSettle();
    final scroll = tester.getRect(walletHomeKey('wallet-home-scroll'));
    expect(scroll.bottom, lessThanOrEqualTo(844 - 34));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 840.0]) {
    for (final textScale in [2.0, 3.0]) {
      testWidgets(
          'English at $width px and ${textScale * 100}% text does not overflow',
          (tester) async {
        final controller = await loadedHomeController(
            repository: HomeTestRepository(data: walletHomeLongFixture));
        await pumpWalletHome(tester,
            controller: controller,
            size: Size(width, 900),
            locale: const Locale('en', 'US'),
            textScale: textScale);
        await tester.pumpAndSettle();
        _expectCompleteAssetAmounts(tester, width);
        expect(tester.takeException(), isNull);
        _expectMatchingActionHeights(tester);
        _expectCompleteTotal(tester, width);
        await tester
            .ensureVisible(find.text(walletHomeLongFixture.coins.first.name));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _expectCompleteAssetAmounts(WidgetTester tester, double width) {
  final coin = walletHomeLongFixture.coins.single;
  final quantity = walletHomeKey('wallet-asset-quantity-${coin.code}');
  final value = walletHomeKey('wallet-asset-value-${coin.code}');
  for (final (target, amount) in [(quantity, coin.bal), (value, coin.fiat)]) {
    final text = tester.widget<Text>(target);
    expect(text.data, amount);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.renderObject<RenderParagraph>(target).didExceedMaxLines,
        isFalse);
    final rect = tester.getRect(target);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
  }
  if (width == 320) {
    expect(tester.getRect(value).top,
        greaterThanOrEqualTo(tester.getRect(quantity).bottom),
        reason: 'Insufficient column width stacks full values below holdings.');
  }
}

void _expectMatchingActionHeights(WidgetTester tester) {
  final receive = tester.getRect(walletHomeKey('wallet-action-receive'));
  for (final key in [
    'wallet-action-receive',
    'wallet-action-transfer',
    'wallet-action-swap',
  ]) {
    final target = walletHomeKey(key);
    final rect = tester.getRect(target);
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(receive.height, closeTo(rect.height, .01),
        reason: 'All three money actions should align when labels wrap.');
    expect(receive.width, closeTo(rect.width, .01));
    expect(receive.top, closeTo(rect.top, .01));
    expect(find.descendant(of: target, matching: find.byType(Text)),
        findsOneWidget);
    expect(
        find.descendant(of: target, matching: find.byType(Icon)), findsNothing,
        reason: 'Money actions use the requested plain text layout.');
  }
}

void _expectCompleteTotal(WidgetTester tester, double width,
    {String currency = 'CNY'}) {
  final target = walletHomeKey('wallet-total-amount');
  final text = tester.widget<Text>(target);
  expect(
      text.data,
      currency == 'USD'
          ? '\$${walletHomeLongFixture.totalBalUsd}'
          : '¥${walletHomeLongFixture.totalBal}');
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(target);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: 'The total estimate must show every digit at large text sizes.');
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
}
