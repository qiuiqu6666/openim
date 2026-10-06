import 'wallet_journal_page.dart';
import 'wallet_journal_query.dart';

abstract interface class WalletJournalSource {
  Future<WalletJournalPage> getJournalPage(WalletJournalQuery query);
}
