/// Optional account-scoped address capability; balance loading stays independent.
abstract interface class WalletTronAddressSource {
  Future<String> getTronAddress();
}
