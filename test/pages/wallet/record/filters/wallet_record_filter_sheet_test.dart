import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/filters/wallet_record_filter_sheet.dart';
import 'package:openim/pages/wallet/record/filters/wallet_record_filters.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/host/wallet_i18n.dart';

import '../fixtures/wallet_record_fixtures.dart';
import '../support/wallet_record_test_support.dart';

void main() {
  testWidgets(
      'apply commits coin and transaction type together without reloading',
      (tester) async {
    await _pumpFilters(tester, size: const Size(390, 2400));
    await tester.pumpAndSettle();
    await _openFilters(tester);
    await _tapOption(tester, 'coin-USDT');
    await _tapOption(tester, 'type-redPacket');

    await _confirm(tester);
    expect(walletRecordKey('wallet-record-filter-sheet'), findsNothing);
    for (final item in walletRecordFixtures) {
      expect(walletRecordKey('wallet-record-${item.id}'),
          item.id == 'january-older' ? findsOneWidget : findsNothing);
    }

    // Reopening the sheet restores the applied draft rather than defaults.
    await _openFilters(tester);
    _expectSelected(tester, 'coin-USDT', true);
    _expectSelected(tester, 'type-redPacket', true);
    await _cancel(tester, '取消');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel discards changed coin, type and date options',
      (tester) async {
    await _pumpFilters(tester, initialCoin: '99', size: const Size(390, 2400));
    await tester.pumpAndSettle();
    await _openFilters(tester);
    await _tapOption(tester, 'coin-USDT');
    await _tapOption(tester, 'type-redPacket');
    await _tapOption(tester, 'date-year');
    await _cancel(tester, '取消');
    for (final item in walletRecordFixtures) {
      expect(
          walletRecordKey('wallet-record-${item.id}'),
          item.coin == '99' || item.coin == '元'
              ? findsOneWidget
              : findsNothing);
    }
    await _openFilters(tester);
    _expectSelected(tester, 'coin-99', true);
    _expectSelected(tester, 'type-all', true);
    _expectSelected(tester, 'date-all', true);
    await _cancel(tester, '取消');

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reset clears advanced filters and month while retaining expenditure direction',
      (tester) async {
    await _pumpFilters(tester,
        initialCoin: 'USDT',
        direction: WalletRecordDirection.expenditure,
        month: DateTime(2026, 1),
        size: const Size(390, 2400));
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-january-newer'), findsOneWidget);
    expect(walletRecordKey('wallet-record-failed-outgoing'), findsNothing);
    await _openFilters(tester);
    await _tapOption(tester, 'type-chainWithdraw');
    await tester.ensureVisible(walletRecordKey('wallet-record-filter-reset'));
    await tester.tap(walletRecordKey('wallet-record-filter-reset'));
    await tester.pumpAndSettle();
    for (final option in ['coin-all', 'type-all', 'date-all']) {
      _expectSelected(tester, option, true);
    }
    await _confirm(tester);
    expect(_selection(tester).coin, isNull);
    expect(_selection(tester).month, isNull);
    expect(_selection(tester).type, HistoryRecordFilter.all);
    for (final item in walletRecordFixtures) {
      expect(walletRecordKey('wallet-record-${item.id}'),
          item.income ? findsNothing : findsOneWidget);
    }
    expect(_selection(tester).direction, WalletRecordDirection.expenditure);

    expect(tester.takeException(), isNull);
  });

  final dateLabels = {
    Locale('zh', 'CN'): ['近7天', '近1个月', '近3个月', '近1年'],
    Locale('zh', 'TW'): ['近7天', '近1個月', '近3個月', '近1年'],
    Locale('en', 'US'): [
      'Last 7 days',
      'Last month',
      'Last 3 months',
      'Last year'
    ],
    Locale('ja', 'JP'): ['過去7日間', '過去1か月', '過去3か月', '過去1年'],
    Locale('ko', 'KR'): ['최근 7일', '최근 1개월', '최근 3개월', '최근 1년'],
  };
  const dateOptions = ['week', 'month', 'threeMonths', 'year'];
  for (final entry in dateLabels.entries) {
    testWidgets(
        'date options and applied summary use localized labels in ${entry.key}',
        (tester) async {
      await _pumpFilters(tester, locale: entry.key);
      await tester.pumpAndSettle();
      for (var index = 0; index < dateOptions.length; index++) {
        await _openFilters(tester);
        final option =
            walletRecordKey('wallet-record-filter-date-${dateOptions[index]}');
        expect(
            find.descendant(
                of: option, matching: find.text(entry.value[index])),
            findsOneWidget);
        await _tapOption(tester, 'date-${dateOptions[index]}');
        await _confirm(tester);
        expect(find.text(entry.value[index]), findsOneWidget);
        expect(find.text(dateOptions[index]), findsNothing,
            reason: 'Internal enum names must not appear as date labels.');
      }

      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('320px 200% text filter sheet remains operable in $brightness',
        (tester) async {
      await _pumpFilters(tester,
          size: const Size(320, 844),
          brightness: brightness,
          locale: const Locale('en', 'US'),
          textScale: 2,
          safePadding: const EdgeInsets.only(top: 44, bottom: 34));
      await tester.pumpAndSettle();
      await _openFilters(tester);
      for (final option in [
        'coin-USDT',
        'type-chainWithdraw',
        'date-threeMonths'
      ]) {
        await _tapOption(tester, option);
        final rect =
            tester.getRect(walletRecordKey('wallet-record-filter-$option'));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.width, greaterThanOrEqualTo(48));
        _expectSelected(tester, option, true);
        expect(tester.takeException(), isNull);
      }
      for (final action in ['reset', 'confirm']) {
        final button = walletRecordKey('wallet-record-filter-$action');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      await _confirm(tester);
      expect(walletRecordKey('wallet-record-filter-sheet'), findsNothing);
      expect(walletRecordKey('wallet-record-empty'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(walletRecordKey('wallet-record-filters'));
  await tester.pumpAndSettle();
  expect(walletRecordKey('wallet-record-filter-sheet'), findsOneWidget);
}

Future<void> _tapOption(WidgetTester tester, String option) async {
  final button = walletRecordKey('wallet-record-filter-$option');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  final button = walletRecordKey('wallet-record-filter-confirm');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _cancel(WidgetTester tester, String tooltip) async {
  final close = find.descendant(
      of: walletRecordKey('wallet-record-filter-sheet'),
      matching: find.byTooltip(tooltip));
  await tester.ensureVisible(close);
  await tester.pumpAndSettle();
  await tester.tap(close);
  await tester.pumpAndSettle();
}

void _expectSelected(WidgetTester tester, String option, bool selected) {
  final semantics = find.ancestor(
      of: walletRecordKey('wallet-record-filter-$option'),
      matching: find.byWidgetPredicate((widget) =>
          widget is Semantics && widget.properties.selected != null));
  expect(
      tester.widget<Semantics>(semantics.first).properties.selected, selected);
}

// The current history page has no advanced-filter toolbar. Exercise the
// retained sheet directly and verify its returned selection against real DTOs.
WalletRecordSelection _selection(WidgetTester tester) =>
    tester.state<_FilterHarnessState>(find.byType(_FilterHarness)).selection;

Future<void> _pumpFilters(
  WidgetTester tester, {
  String? initialCoin,
  WalletRecordDirection direction = WalletRecordDirection.all,
  DateTime? month,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
  EdgeInsets safePadding = EdgeInsets.zero,
}) =>
    pumpWalletRecords(tester,
        size: size,
        brightness: brightness,
        locale: locale,
        textScale: textScale,
        safePadding: safePadding,
        home: _FilterHarness(
            initial: WalletRecordSelection(
                coin: initialCoin, direction: direction, month: month)));

class _FilterHarness extends StatefulWidget {
  const _FilterHarness({required this.initial});
  final WalletRecordSelection initial;
  @override
  State<_FilterHarness> createState() => _FilterHarnessState();
}

class _FilterHarnessState extends State<_FilterHarness> {
  late WalletRecordSelection selection = widget.initial;
  final now = DateTime(2026, 2, 10);
  @override
  Widget build(BuildContext context) {
    final records = walletRecordFixtures
        .where((record) => selection.matches(record, now: now))
        .toList();
    return Scaffold(
        body: Column(children: [
      TextButton(
          key: const ValueKey('wallet-record-filters'),
          onPressed: () async {
            final result = await showModalBottomSheet<WalletRecordSelection>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => WalletRecordFilterSheet(
                    selection: selection,
                    coinOptions: const ['99', 'USDT'],
                    now: now));
            if (mounted && result != null) setState(() => selection = result);
          },
          child: const Text('Open filter component')),
      if (selection.datePreset != WalletHistoryDatePreset.all)
        Text(
            walletRecordDatePresetLabel(selection.datePreset, AppI18n.current)),
      if (records.isEmpty) const SizedBox(key: ValueKey('wallet-record-empty')),
      for (final record in records)
        SizedBox(key: ValueKey('wallet-record-${record.id}')),
    ]));
  }
}
