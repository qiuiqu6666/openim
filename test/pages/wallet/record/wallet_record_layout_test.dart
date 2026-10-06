import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/wallet_record_fixtures.dart';
import 'support/wallet_record_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final locale in walletRecordLocales) {
      testWidgets(
          '320px ledger preserves long amounts and safe areas in $locale $brightness',
          (tester) async {
        await pumpWalletRecords(tester,
            repository:
                RecordTestRepository(records: [walletRecordLongFixture]),
            size: const Size(320, 844),
            brightness: brightness,
            locale: locale,
            textScale: 2,
            safePadding: const EdgeInsets.only(top: 44, bottom: 34));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final appBarTitle =
            tester.widget<AppBar>(find.byType(AppBar)).title! as Text;
        final title = find.descendant(
            of: find.byType(AppBar), matching: find.text(appBarTitle.data!));
        expect(title, findsOneWidget);
        expect(appBarTitle.overflow, isNot(TextOverflow.ellipsis));
        _expectFullParagraph(tester, title, 'The full localized page title');
        final titleRect = tester.getRect(title);
        expect(titleRect.left, greaterThanOrEqualTo(0));
        expect(titleRect.right, lessThanOrEqualTo(320));
        for (final key in [
          'wallet-record-tab-all',
          'wallet-record-tab-expenditure',
          'wallet-record-tab-income',
          'wallet-record-support',
          'wallet-record-filters',
          'wallet-record-month-picker-2026-10',
        ]) {
          final rect = tester.getRect(walletRecordKey(key));
          expect(rect.left, greaterThanOrEqualTo(0), reason: key);
          expect(rect.right, lessThanOrEqualTo(320), reason: key);
          expect(rect.top, greaterThanOrEqualTo(44), reason: key);
          expect(rect.height, greaterThanOrEqualTo(48), reason: key);
          expect(rect.width, greaterThanOrEqualTo(48), reason: key);
        }
        final amount = walletRecordKey('wallet-record-amount-long-amount');
        await tester.ensureVisible(amount);
        await tester.pumpAndSettle();
        final text = tester.widget<Text>(amount);
        const expectedAmount = '+123,456,789,012,345,678.12 USDT';
        expect(text.data?.replaceAll('\u200B', ''), expectedAmount);
        expect(text.semanticsLabel, expectedAmount,
            reason:
                'Spoken amounts must exclude the display-only line breaks.');
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        _expectFullParagraph(tester, amount, 'Every amount digit');
        final rect = tester.getRect(amount);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(844 - 34));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'direction tabs expose selected state and sufficient touch targets in $brightness',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpWalletRecords(tester,
            repository: RecordTestRepository(), brightness: brightness);
        await tester.pumpAndSettle();
        for (final selected in ['all', 'income', 'expenditure']) {
          if (selected != 'all') {
            await tester.tap(walletRecordKey('wallet-record-tab-$selected'));
            await tester.pumpAndSettle();
          }
          for (final direction in ['all', 'income', 'expenditure']) {
            final tab = walletRecordKey('wallet-record-tab-$direction');
            expect(
                tester
                        .getSemantics(tab)
                        .getSemanticsData()
                        .flagsCollection
                        .isSelected ==
                    Tristate.isTrue,
                direction == selected);
            final rect = tester.getRect(tab);
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.width, greaterThanOrEqualTo(48));
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}

void _expectFullParagraph(WidgetTester tester, Finder text, String label) {
  final data = tester.widget<Text>(text).data!;
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)));
  expect(paragraph.didExceedMaxLines, isFalse, reason: label);
  // Selection boxes include trailing spaces beyond a wrapped line, which is
  // different from painted glyph ink. Check every visible character against
  // the original display data; paragraph/viewport rects verify vertical fit.
  for (final character
      in RegExp(r'[^\s\u200B]', unicode: true).allMatches(data)) {
    for (final box in paragraph.getBoxesForSelection(TextSelection(
        baseOffset: character.start, extentOffset: character.end))) {
      expect(box.left, greaterThanOrEqualTo(-.01), reason: label);
      expect(box.right, lessThanOrEqualTo(paragraph.size.width + .01),
          reason: label);
    }
  }
}
