/// Describes which real history source an adapter can supply. Repositories
/// injected by existing tests remain unrestricted unless they opt into this.
abstract interface class WalletHistorySourceBoundary {
  bool get hasCompleteLedger;
  bool get hasWithdrawalHistory;
  int get depositRecordLimit;
}
