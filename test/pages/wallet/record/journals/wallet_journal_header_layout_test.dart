import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/wallet_record_test_support.dart';
import 'support/wallet_journal_test_support.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final language in const [
    (locale: Locale('zh', 'CN'), history: '历史记录', coin: 'TRX变动'),
    (locale: Locale('en', 'US'), history: 'History', coin: 'TRX changes'),
  ]) {
    testWidgets(
        '320px journal history and coin titles retain direction queries at 200% in ${language.locale}',
        (tester) async {
      final repository = JournalTestRepository();
      repository.respond = (query) async {
        if (query.direction != null) {
          return journalTestPage([
            journalTestEntry('selected-income', direction: query.direction!),
          ]);
        }
        if (query.cursor != null) {
          return journalTestPage([journalTestEntry('next-page')]);
        }
        return journalTestPage(
            List.generate(
                8, (index) => journalTestEntry('initial-page-$index')),
            hasMore: true,
            cursor: 'before-direction-cursor');
      };
      await pumpWalletRecords(tester,
          repository: repository,
          locale: language.locale,
          size: const Size(320, 844),
          textScale: 2,
          safePadding: const EdgeInsets.only(top: 44, bottom: 34));
      await tester.pumpAndSettle();
      _expectHeader(tester, language.history);
      expect(repository.queries, hasLength(1));
      expect(repository.queries.single.cursor, isNull);

      // Scroll a real journal page before changing direction, ensuring that
      // the new query cannot inherit the page cursor.
      for (var scroll = 0;
          scroll < 20 && repository.queries.length == 1;
          scroll++) {
        await tester.drag(
            walletRecordKey('wallet-record-scroll'), const Offset(0, -350));
        await tester.pumpAndSettle();
      }
      expect(repository.queries, hasLength(2));
      expect(repository.queries.last.cursor, 'before-direction-cursor');

      await tester.tap(walletRecordKey('wallet-record-tab-income'));
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(3));
      expect(repository.queries.last.direction, 'income');
      expect(repository.queries.last.currency, isNull);
      expect(repository.queries.last.cursor, isNull);
      expect(walletRecordKey('wallet-record-selected-income'), findsOneWidget);
      _expectHeader(tester, language.history);
      expect(repository.depositCalls, 0);
      expect(repository.withdrawCalls, 0);
      expect(tester.takeException(), isNull);

      // A currency-specific entry keeps the real API currency when the same
      // accessible direction controls are used.
      await tester.pumpWidget(const SizedBox.shrink());
      final currencyRepository = JournalTestRepository()
        ..respond = (query) async => journalTestPage([
              journalTestEntry('coin-event',
                  currency: 'TRX', direction: query.direction ?? 'income'),
            ]);
      await pumpWalletRecords(tester,
          repository: currencyRepository,
          initialCoin: 'TRX',
          locale: language.locale,
          size: const Size(320, 844),
          textScale: 2,
          safePadding: const EdgeInsets.only(top: 44, bottom: 34));
      await tester.pumpAndSettle();
      _expectHeader(tester, language.coin);
      expect(currencyRepository.queries.single.currency, 'TRX');
      await tester.tap(walletRecordKey('wallet-record-tab-expenditure'));
      await tester.pumpAndSettle();
      expect(currencyRepository.queries, hasLength(2));
      expect(currencyRepository.queries.last.currency, 'TRX');
      expect(currencyRepository.queries.last.direction, 'expense');
      expect(currencyRepository.queries.last.cursor, isNull);
      _expectHeader(tester, language.coin);
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectHeader(WidgetTester tester, String expectedTitle) {
  final title = walletRecordKey('wallet-journal-list-title');
  expect(title, findsOneWidget);
  final text = tester.widget<Text>(title);
  expect(text.data, expectedTitle);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: title, matching: find.byType(RichText)));
  expect(paragraph.didExceedMaxLines, isFalse);
  for (final character in RegExp(r'\S').allMatches(expectedTitle)) {
    final boxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: character.start, extentOffset: character.end));
    expect(boxes, isNotEmpty,
        reason: 'Every visible title character must be laid out.');
    for (final box in boxes) {
      expect(box.left, greaterThanOrEqualTo(-.01));
      expect(box.right, lessThanOrEqualTo(paragraph.size.width + .01));
    }
  }
  final titleRect = tester.getRect(title);
  expect(titleRect.left, greaterThanOrEqualTo(0));
  expect(titleRect.right, lessThanOrEqualTo(320));
  expect(walletRecordKey('wallet-record-filters'), findsNothing);
  expect(walletRecordKey('wallet-record-support'), findsNothing);
  expect(walletRecordKey('wallet-record-clear-filters'), findsNothing);
  final tabRects = <Rect>[];
  for (final direction in ['all', 'income', 'expenditure']) {
    final tab = walletRecordKey('wallet-record-tab-$direction');
    expect(tab.hitTestable(), findsOneWidget);
    final button = find.descendant(of: tab, matching: find.byType(TextButton));
    expect(button, findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    final rect = tester.getRect(tab);
    expect(rect.width, greaterThanOrEqualTo(48), reason: direction);
    expect(rect.height, greaterThanOrEqualTo(48), reason: direction);
    expect(rect.left, greaterThanOrEqualTo(0), reason: direction);
    expect(rect.right, lessThanOrEqualTo(320), reason: direction);
    expect(rect.top, greaterThanOrEqualTo(44), reason: direction);
    expect(rect.bottom, lessThanOrEqualTo(844 - 34), reason: direction);
    expect(titleRect.overlaps(rect), isFalse, reason: direction);
    for (final previous in tabRects) {
      expect(previous.overlaps(rect), isFalse);
    }
    tabRects.add(rect);
  }
}
