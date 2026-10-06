/// Account-scoped sources must not publish data into another login session.
abstract interface class WalletSessionSource {
  String get ownerAccountKey;
  bool get isCurrentAccount;
}

class WalletAccountChangedException implements Exception {
  const WalletAccountChangedException();
}
