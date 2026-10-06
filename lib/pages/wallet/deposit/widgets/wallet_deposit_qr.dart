import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/wallet_fund_api.dart';
import '../../widgets/wallet_coin_logo.dart';
import '../../host/wallet_i18n.dart';
import '../../wallet_repository.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../wallet_deposit_tokens.dart';

/// Encodes the allocated address with enough correction for the coin mark.
class WalletDepositQr extends StatelessWidget {
  const WalletDepositQr({
    super.key,
    required this.address,
    required this.currency,
    this.size = WalletDepositTokens.qrSize,
    this.quietZone = WalletDepositTokens.qrQuietZone,
  });

  final WalletDepositAddress address;
  final FundCurrency currency;
  final double size;
  final double quietZone;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Semantics(
      label: i18n.format(
        zhHans: '{code} 充值地址二维码，网络 {network}',
        zhHant: '{code} 儲值地址二維碼，網路 {network}',
        en: '{code} deposit address QR code on {network}',
        ja: '{network}の{code}入金アドレスQRコード',
        ko: '{network}의 {code} 입금 주소 QR 코드',
        vars: {'code': currency.code, 'network': address.network},
      ),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              QrImageView(
                key: const ValueKey('wallet-deposit-qr'),
                data: address.address,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.H,
                size: size,
                padding: EdgeInsets.all(quietZone),
                backgroundColor: WalletDepositTokens.qrBackground,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: WalletDepositTokens.qrInk,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: WalletDepositTokens.qrInk,
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: WalletDepositTokens.qrBackground,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.s2),
                  child: WalletCoinLogo(
                    type: currency == FundCurrency.trx
                        ? CoinType.trx
                        : CoinType.usdt,
                    size: WalletDepositTokens.qrLogo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
