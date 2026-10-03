import '../wallet_models.dart';
import '../wallet_repository.dart';

class WalletApi {
  WalletApi._();
  static final WalletApi instance = WalletApi._();

  Future<WalletMe> getMe() =>
      Future<WalletMe>.error(const WalletBackendUnavailableException());
}
