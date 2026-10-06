import '../wallet_models.dart';
import '../wallet_repository.dart';

class WalletApi {
  WalletApi._();
  static final WalletApi instance = WalletApi._();

  // The old aggregated /wallet/me contract is not exposed by Chat fund APIs.
  // It cannot safely invent a quote, minimum deposit or payment-password flag.
  // Real Wallet flows use WalletFundApi and the payment-password service.
  Future<WalletMe> getMe() =>
      Future<WalletMe>.error(const WalletBackendUnavailableException());
}
