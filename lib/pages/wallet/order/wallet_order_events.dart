import '../../../services/fund/fund_refresh_events.dart';

class WalletOrderEvents {
  WalletOrderEvents._();
  static String get currentAccountKey => FundRefreshEvents.currentAccountKey;
  static Stream<String> get balanceChanges => FundRefreshEvents.balanceChanges;
  static Stream<String> get recordChanges => FundRefreshEvents.recordChanges;
  static void notifyBalance({String? accountKey}) =>
      FundRefreshEvents.notifyBalance(accountKey: accountKey);
  static void notifyRecord({String? accountKey}) =>
      FundRefreshEvents.notifyRecord(accountKey: accountKey);
}
