import '../../wallet_time.dart';
import '../wallet_record_models.dart';

enum WalletRecordDirection { all, expenditure, income }

enum WalletHistoryDatePreset { all, week, month, threeMonths, year }

String walletRecordNormalizeCoin(String coin) {
  final raw = coin.trim();
  if (raw.isEmpty) return raw;
  if (raw == '元' || raw.toUpperCase() == '99' || raw.toUpperCase() == 'BI99') {
    return '99';
  }
  return raw.toUpperCase();
}

/// Ledger timestamps retain the API's Instant convention, including epoch
/// values and suffix-less UTC wall-clock strings.
DateTime? walletRecordDateTime(WalletRecordDto item) => item.journal != null
    ? DateTime.fromMillisecondsSinceEpoch(item.journal!.createdAt).toLocal()
    : parseWalletApiTimeToLocal(item.time);

/// A local filter choice; it never changes the underlying ledger records.
class WalletRecordSelection {
  const WalletRecordSelection({
    this.direction = WalletRecordDirection.all,
    this.coin,
    this.type = HistoryRecordFilter.all,
    this.datePreset = WalletHistoryDatePreset.all,
    this.month,
    this.journalBizType,
    this.journalType,
    this.journalDirection,
  });

  final WalletRecordDirection direction;
  final String? coin;
  final HistoryRecordFilter type;
  final WalletHistoryDatePreset datePreset;
  final DateTime? month;
  final String? journalBizType;
  final String? journalType;
  final String? journalDirection;

  WalletRecordSelection copyWith({
    WalletRecordDirection? direction,
    String? coin,
    HistoryRecordFilter? type,
    WalletHistoryDatePreset? datePreset,
    DateTime? month,
    bool clearCoin = false,
    bool clearMonth = false,
    String? journalBizType,
    String? journalType,
    String? journalDirection,
    bool clearJournalBizType = false,
    bool clearJournalType = false,
    bool clearJournalDirection = false,
  }) =>
      WalletRecordSelection(
        direction: direction ?? this.direction,
        coin: clearCoin ? null : coin ?? this.coin,
        type: type ?? this.type,
        datePreset: datePreset ?? this.datePreset,
        month: clearMonth ? null : month ?? this.month,
        journalBizType:
            clearJournalBizType ? null : journalBizType ?? this.journalBizType,
        journalType: clearJournalType ? null : journalType ?? this.journalType,
        journalDirection: clearJournalDirection
            ? null
            : journalDirection ?? this.journalDirection,
      );

  bool matches(WalletRecordDto item, {required DateTime now}) {
    final journal = item.journal;
    if (direction == WalletRecordDirection.income &&
        (journal == null ? !item.income : journal.direction != 'income')) {
      return false;
    }
    if (direction == WalletRecordDirection.expenditure &&
        (journal == null ? item.income : journal.direction != 'expense')) {
      return false;
    }
    if (journal != null &&
        ((journalBizType != null && journal.bizType != journalBizType) ||
            (journalType != null && journal.type != journalType) ||
            (journalDirection != null &&
                journal.direction != journalDirection))) {
      return false;
    }
    final selectedCoin = walletRecordNormalizeCoin(coin ?? '');
    if (selectedCoin.isNotEmpty &&
        walletRecordNormalizeCoin(item.coin) != selectedCoin) {
      return false;
    }
    if (!_matchesType(item)) return false;
    if (month == null && datePreset == WalletHistoryDatePreset.all) return true;

    final time = walletRecordDateTime(item);
    // Undated records belong only to the unrestricted date view.
    if (time == null) return false;
    final selectedMonth = month;
    if (selectedMonth != null &&
        (time.year != selectedMonth.year ||
            time.month != selectedMonth.month)) {
      return false;
    }
    final range = dateRange(now);
    return range == null ||
        (!time.isBefore(range.start) && time.isBefore(range.end));
  }

  ({DateTime start, DateTime end})? dateRange(DateTime now) {
    final presetRange = _dateRange(datePreset, now);
    final selectedMonth = month;
    if (selectedMonth == null) return presetRange;
    var start = DateTime(selectedMonth.year, selectedMonth.month);
    var end = DateTime(selectedMonth.year, selectedMonth.month + 1);
    if (presetRange != null) {
      if (presetRange.start.isAfter(start)) start = presetRange.start;
      if (presetRange.end.isBefore(end)) end = presetRange.end;
    }
    return (start: start, end: end.isBefore(start) ? start : end);
  }

  bool _matchesType(WalletRecordDto item) => switch (type) {
        HistoryRecordFilter.all => true,
        HistoryRecordFilter.chainWithdraw => item.isChainWithdraw,
        HistoryRecordFilter.chainDeposit => item.isChainDeposit,
        HistoryRecordFilter.internalDeposit => item.isInternalReceive,
        HistoryRecordFilter.internalWithdraw => item.isInternalTransfer,
        HistoryRecordFilter.redPacket =>
          item.type == WalletRecordType.redPacket && !item.isRedPacketRefund,
        HistoryRecordFilter.redPacketRefund => item.isRedPacketRefund,
        HistoryRecordFilter.transfer =>
          item.type == WalletRecordType.transfer ||
              item.type == WalletRecordType.receive,
        HistoryRecordFilter.transferRefund => item.title.contains('退款') ||
            item.title.toLowerCase().contains('refund'),
      };
}

({DateTime start, DateTime end})? _dateRange(
    WalletHistoryDatePreset preset, DateTime now) {
  if (preset == WalletHistoryDatePreset.all) return null;
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  final end = DateTime(today.year, today.month, today.day + 1);
  final start = switch (preset) {
    WalletHistoryDatePreset.week =>
      DateTime(today.year, today.month, today.day - 6),
    WalletHistoryDatePreset.month => _shiftMonthsClamped(today, -1),
    WalletHistoryDatePreset.threeMonths => _shiftMonthsClamped(today, -3),
    WalletHistoryDatePreset.year => _shiftMonthsClamped(today, -12),
    WalletHistoryDatePreset.all => today,
  };
  // Calendar-midnight construction also preserves boundaries across DST.
  return (start: start, end: end);
}

DateTime _shiftMonthsClamped(DateTime date, int months) {
  final target = DateTime(date.year, date.month + months);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(target.year, target.month, day);
}

/// A calendar-month bucket, with a separate bucket for unknown timestamps.
class WalletRecordMonthGroup {
  WalletRecordMonthGroup({
    required this.key,
    required this.month,
    required List<WalletRecordDto> records,
  }) : records = List<WalletRecordDto>.unmodifiable(records);

  final String key;
  final DateTime? month;
  final List<WalletRecordDto> records;
}

/// Sort real local timestamps newest first, keeping input order for ties and
/// unknown dates. Group identities include the year so years never merge.
List<WalletRecordMonthGroup> walletRecordGroupMonths(
    List<WalletRecordDto> records) {
  final ordered = <({WalletRecordDto item, DateTime? time, int index})>[
    for (var index = 0; index < records.length; index++)
      (
        item: records[index],
        time: walletRecordDateTime(records[index]),
        index: index,
      ),
  ];
  ordered.sort((a, b) {
    final aTime = a.time, bTime = b.time;
    if (aTime == null) return bTime == null ? a.index.compareTo(b.index) : 1;
    if (bTime == null) return -1;
    final comparison = bTime.compareTo(aTime);
    return comparison == 0 ? a.index.compareTo(b.index) : comparison;
  });

  final buckets = <String, List<WalletRecordDto>>{};
  final months = <String, DateTime?>{};
  for (final entry in ordered) {
    final time = entry.time;
    final key = time == null
        ? 'unknown'
        : '${time.year.toString().padLeft(4, '0')}-'
            '${time.month.toString().padLeft(2, '0')}';
    (buckets[key] ??= []).add(entry.item);
    months[key] = time == null ? null : DateTime(time.year, time.month);
  }
  return List<WalletRecordMonthGroup>.unmodifiable([
    for (final entry in buckets.entries)
      WalletRecordMonthGroup(
          key: entry.key, month: months[entry.key], records: entry.value),
  ]);
}
