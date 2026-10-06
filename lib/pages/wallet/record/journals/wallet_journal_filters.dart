import '../filters/wallet_record_filters.dart';
import 'wallet_journal_query.dart';

WalletJournalQuery walletJournalQueryForSelection(
  WalletRecordSelection selection, {
  required DateTime now,
  String? fixedBizType,
}) {
  final coin = walletRecordNormalizeCoin(selection.coin ?? '');
  final range = selection.dateRange(now);
  return WalletJournalQuery(
    currency: coin.isEmpty
        ? null
        : coin == '99'
            ? 'BI99'
            : coin,
    bizType: fixedBizType ?? selection.journalBizType,
    type: selection.journalType,
    direction: switch (selection.direction) {
      WalletRecordDirection.income => 'income',
      WalletRecordDirection.expenditure => 'expense',
      WalletRecordDirection.all => selection.journalDirection,
    },
    startTime: range?.start.millisecondsSinceEpoch,
    endTime: range?.end.millisecondsSinceEpoch,
  );
}
