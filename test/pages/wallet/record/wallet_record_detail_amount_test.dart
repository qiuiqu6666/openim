import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';

import 'fixtures/wallet_record_fixtures.dart';
import 'support/wallet_record_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final coin in ['99', 'USDT']) {
      for (final example in const [
        (raw: '+28.505', rounded: '+28.51'),
        (raw: '8', rounded: '8.00'),
      ]) {
        testWidgets(
            'actual $coin detail formats ${example.raw} with two decimals in $brightness',
            (tester) async {
          final item = walletRecordFixture(
              id: 'detail-short', coin: coin, amount: example.raw, time: '');
          final repository = RecordTestRepository(records: [item]);
          await _openDetail(tester,
              item: item, repository: repository, brightness: brightness);
          final amount = tester
              .widget<Text>(walletRecordKey('wallet-record-detail-amount'));
          final expected = '${example.rounded}${coin == '99' ? '' : ' USDT'}';
          expect(amount.data?.replaceAll('\u200B', ''), expected);
          expect(amount.semanticsLabel, expected);
          expect(item.amount, example.raw,
              reason: 'Display formatting must not mutate the repository DTO.');
          expectRecordRequests(repository, 1);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets(
          'actual long $coin detail keeps every visible digit at 320px in $brightness',
          (tester) async {
        const raw = '-123,456,789,012,345,678.123456789000';
        final item = walletRecordFixture(
            id: 'detail-long', coin: coin, amount: raw, time: '');
        final repository = RecordTestRepository(records: [item]);
        await _openDetail(tester,
            item: item,
            repository: repository,
            brightness: brightness,
            size: const Size(320, 844),
            textScale: 2);
        final finder = walletRecordKey('wallet-record-detail-amount');
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final amount = tester.widget<Text>(finder);
        final expected =
            '-123,456,789,012,345,678.12${coin == '99' ? '' : ' USDT'}';
        expect(amount.data?.replaceAll('\u200B', ''), expected);
        expect(amount.semanticsLabel, expected);
        expect(amount.overflow, isNot(TextOverflow.ellipsis));
        final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: finder, matching: find.byType(RichText)));
        expect(paragraph.didExceedMaxLines, isFalse);
        // A wrapped trailing space's selection box can extend past the line;
        // check the visible characters rather than that unpainted whitespace.
        for (final character
            in RegExp(r'[^\s\u200B]', unicode: true).allMatches(amount.data!)) {
          for (final box in paragraph.getBoxesForSelection(TextSelection(
              baseOffset: character.start, extentOffset: character.end))) {
            expect(box.left, greaterThanOrEqualTo(-.01));
            expect(box.right, lessThanOrEqualTo(paragraph.size.width + .01));
          }
        }
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.top, greaterThanOrEqualTo(44));
        expect(rect.bottom, lessThanOrEqualTo(844 - 34));
        expect(item.amount, raw);
        expectRecordRequests(repository, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _openDetail(WidgetTester tester,
    {required WalletRecordDto item,
    required RecordTestRepository repository,
    required Brightness brightness,
    Size size = const Size(390, 844),
    double textScale = 1}) async {
  await pumpWalletRecords(tester,
      repository: repository,
      brightness: brightness,
      size: size,
      textScale: textScale,
      safePadding: const EdgeInsets.only(top: 44, bottom: 34));
  await settleWalletRecordImages(tester);
  final row = walletRecordKey('wallet-record-${item.id}');
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(find.byType(WalletRecordDetailScreen), findsOneWidget);
  expect(
      tester
          .widget<WalletRecordDetailScreen>(
              find.byType(WalletRecordDetailScreen))
          .item,
      same(item));
  expect(walletRecordKey('wallet-record-detail-amount'), findsOneWidget);
}
