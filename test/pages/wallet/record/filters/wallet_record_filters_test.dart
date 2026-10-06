import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/filters/wallet_record_filters.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';

import '../fixtures/wallet_record_fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 7, 15);

  test('unrestricted selection includes old and unknown dates', () {
    const selection = WalletRecordSelection();
    expect(
        walletRecordFixtures.every((item) => selection.matches(item, now: now)),
        isTrue);
    expect(
        selection.matches(walletRecordFixture(time: 'invalid time'), now: now),
        isTrue);
  });

  test('direction follows income even when the transaction type says otherwise',
      () {
    final incomingTransfer =
        walletRecordFixture(income: true, type: WalletRecordType.transfer);
    final outgoingReceive =
        walletRecordFixture(income: false, type: WalletRecordType.receive);
    const income =
        WalletRecordSelection(direction: WalletRecordDirection.income);
    const expenditure =
        WalletRecordSelection(direction: WalletRecordDirection.expenditure);
    expect(income.matches(incomingTransfer, now: now), isTrue);
    expect(income.matches(outgoingReceive, now: now), isFalse);
    expect(expenditure.matches(incomingTransfer, now: now), isFalse);
    expect(expenditure.matches(outgoingReceive, now: now), isTrue);
  });

  test('platform aliases normalize without mixing another token', () {
    for (final coin in ['99', ' 元 ']) {
      final selection = WalletRecordSelection(coin: coin);
      expect(
          selection.matches(walletRecordFixture(coin: '99'), now: now), isTrue);
      expect(
          selection.matches(walletRecordFixture(coin: '元'), now: now), isTrue);
      expect(selection.matches(walletRecordFixture(coin: 'USDT'), now: now),
          isFalse);
    }
    expect(walletRecordNormalizeCoin(' usdt '), 'USDT');
    expect(walletRecordNormalizeCoin(' '), '');
  });

  test(
      'actual dates sort months and rows across years, with unknown dates last',
      () {
    final groups = walletRecordGroupMonths(walletRecordFixtures);
    expect(groups.map((group) => group.key),
        ['2026-10', '2026-01', '2025-12', '2025-01', 'unknown']);
    expect(groups[1].records.map((item) => item.id),
        ['january-newer', 'january-older']);
    expect(groups[1].month, DateTime(2026, 1));
    expect(groups[3].month, DateTime(2025, 1));
    expect(groups.last.month, isNull);
    expect(groups.last.records.single.id, 'unknown-time');
    expect(() => groups.first.records.clear(), throwsUnsupportedError);
  });

  test('sorting preserves input order for equal instants and unknown dates',
      () {
    final first =
        walletRecordFixture(id: 'first', time: '2026-10-05T09:00:00Z');
    final second =
        walletRecordFixture(id: 'second', time: '2026-10-05T17:00:00+08:00');
    final undated = walletRecordFixture(id: 'undated', time: '');
    final invalid = walletRecordFixture(id: 'invalid', time: 'unknown');
    final groups = walletRecordGroupMonths([undated, first, invalid, second]);
    expect(groups.first.records, [first, second]);
    expect(groups.last.records, [undated, invalid]);
  });

  test(
      'epoch seconds, epoch milliseconds and explicit timezones identify the same instant',
      () {
    final utc = DateTime.utc(2026, 1, 1, 0, 30);
    for (final time in [
      '${utc.millisecondsSinceEpoch ~/ 1000}',
      '${utc.millisecondsSinceEpoch}',
      '2026-01-01T08:30:00+08:00',
      '2026-01-01T00:30:00Z',
    ]) {
      expect(
          walletRecordDateTime(walletRecordFixture(time: time)), utc.toLocal());
    }
    // Suffix-less API Instant strings retain the UTC convention too.
    expect(
        walletRecordDateTime(walletRecordFixture(time: '2026-01-01 00:30:00')),
        utc.toLocal());
  });

  test('selected calendar month includes its year and excludes unknown dates',
      () {
    final selection = WalletRecordSelection(month: DateTime(2026, 1));
    expect(
        walletRecordFixtures
            .where((item) => selection.matches(item, now: now))
            .map((item) => item.id),
        ['january-older', 'january-newer']);
    expect(selection.matches(walletRecordFixture(time: ''), now: now), isFalse);
    expect(selection.matches(walletRecordFixture(time: 'invalid'), now: now),
        isFalse);
  });

  test('week includes local midnight start and excludes next midnight end', () {
    const selection =
        WalletRecordSelection(datePreset: WalletHistoryDatePreset.week);
    final start = DateTime(2026, 10, 1);
    final end = DateTime(2026, 10, 8);
    expect(selection.matches(_at(start), now: now), isTrue);
    expect(
        selection.matches(_at(start.subtract(const Duration(microseconds: 1))),
            now: now),
        isFalse);
    expect(
        selection.matches(_at(end.subtract(const Duration(microseconds: 1))),
            now: now),
        isTrue);
    expect(selection.matches(_at(end), now: now), isFalse);
    expect(selection.matches(walletRecordFixture(time: ''), now: now), isFalse);
  });

  for (final scenario in [
    (
      preset: WalletHistoryDatePreset.month,
      now: DateTime(2026, 3, 31, 12),
      start: DateTime(2026, 2, 28)
    ),
    (
      preset: WalletHistoryDatePreset.month,
      now: DateTime(2024, 3, 31, 12),
      start: DateTime(2024, 2, 29)
    ),
    (
      preset: WalletHistoryDatePreset.threeMonths,
      now: DateTime(2026, 5, 31, 12),
      start: DateTime(2026, 2, 28)
    ),
    (
      preset: WalletHistoryDatePreset.year,
      now: DateTime(2024, 2, 29, 12),
      start: DateTime(2023, 2, 28)
    ),
  ]) {
    test(
        '${scenario.preset.name} clamps a missing calendar day for ${scenario.now}',
        () {
      final selection = WalletRecordSelection(datePreset: scenario.preset);
      expect(selection.matches(_at(scenario.start), now: scenario.now), isTrue);
      expect(
          selection.matches(
              _at(scenario.start.subtract(const Duration(microseconds: 1))),
              now: scenario.now),
          isFalse);
      final end =
          DateTime(scenario.now.year, scenario.now.month, scenario.now.day + 1);
      expect(selection.matches(_at(end), now: scenario.now), isFalse);
    });
  }

  test('advanced transaction type composes with direction and coin selection',
      () {
    const selection = WalletRecordSelection(
      direction: WalletRecordDirection.expenditure,
      coin: '99',
      type: HistoryRecordFilter.transfer,
    );
    expect(
        selection.matches(
            walletRecordFixture(type: WalletRecordType.receive, income: false),
            now: now),
        isTrue);
    expect(
        selection.matches(
            walletRecordFixture(
                type: WalletRecordType.redPacket, income: false),
            now: now),
        isFalse);
    expect(
        selection.matches(
            walletRecordFixture(type: WalletRecordType.receive, income: true),
            now: now),
        isFalse);
    expect(
        selection.matches(
            walletRecordFixture(
                type: WalletRecordType.receive, income: false, coin: 'USDT'),
            now: now),
        isFalse);
  });

  test(
      'clearing month and coin restores unknown-date eligibility without dropping direction',
      () {
    final selection = WalletRecordSelection(
      direction: WalletRecordDirection.income,
      coin: '99',
      month: DateTime(2026, 1),
    );
    final cleared = selection.copyWith(clearMonth: true, clearCoin: true);
    expect(cleared.direction, WalletRecordDirection.income);
    expect(
        cleared.matches(walletRecordFixture(time: '', coin: 'USDT'), now: now),
        isTrue);
    expect(
        cleared.matches(walletRecordFixture(time: '', income: false), now: now),
        isFalse);
  });
}

WalletRecordDto _at(DateTime local) =>
    walletRecordFixture(time: local.toUtc().toIso8601String());
