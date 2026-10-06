import 'package:openim/pages/wallet/data/wallet_session_source.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_page.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_query.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_source.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

class JournalTestRepository extends UnavailableWalletRepository
    implements WalletJournalSource, WalletSessionSource {
  final List<WalletJournalQuery> queries = [];
  Future<WalletJournalPage> Function(WalletJournalQuery query)? respond;
  bool currentAccount = true;
  int depositCalls = 0;
  int withdrawCalls = 0;

  @override
  String get ownerAccountKey => 'test:journal-owner';
  @override
  bool get isCurrentAccount => currentAccount;
  @override
  Future<WalletJournalPage> getJournalPage(WalletJournalQuery query) {
    queries.add(query);
    return respond?.call(query) ?? Future.value(journalTestPage([]));
  }

  @override
  Future<List<WalletRecordDto>> getDepositRecords() {
    depositCalls++;
    return super.getDepositRecords();
  }

  @override
  Future<List<WalletRecordDto>> getWithdrawRecords() {
    withdrawCalls++;
    return super.getWithdrawRecords();
  }
}

WalletJournalEntry journalTestEntry(String id,
    {String currency = 'USDT',
    String direction = 'income',
    String type = 'admin_adjust'}) {
  final isFreeze = direction == 'freeze' || direction == 'unfreeze';
  final debit = direction == 'expense' || direction == 'freeze';
  return WalletJournalEntry.fromJson({
    'id': id,
    'currency': currency,
    'bizType': type.startsWith('packet_') ? 'packet_normal' : 'admin_adjust',
    'type': type,
    'title': '事件 $id',
    'direction': direction,
    'amount': '8',
    'availableDelta': debit ? '-8' : '8',
    'frozenDelta': isFreeze ? (debit ? '8' : '-8') : '0',
    'assetDelta': isFreeze ? '0' : (debit ? '-8' : '8'),
    'beforeAvailable': null,
    'afterAvailable': null,
    'createdAt': DateTime.utc(2026, 10, 5, 12).millisecondsSinceEpoch,
    'bizID': '$id:event',
    'orderID': 'shared-order',
    'counterpartyID': '',
    'groupID': '',
    'remark': '',
    'reason': '',
    'orderStatus': '',
    'chainTxID': '',
  });
}

WalletJournalPage journalTestPage(List<WalletJournalEntry> entries,
        {bool hasMore = false, String cursor = '', int limit = 20}) =>
    WalletJournalPage(
        items: entries,
        limit: limit,
        hasMore: hasMore,
        nextCursor: hasMore ? cursor : '');
