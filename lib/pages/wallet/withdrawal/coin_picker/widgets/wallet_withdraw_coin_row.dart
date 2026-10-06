import 'package:flutter/material.dart';

import '../../../widgets/wallet_coin_logo.dart';
import '../../../host/wallet_i18n.dart';
import '../../../wallet_repository.dart';
import '../../../widgets/coin_picker/wallet_coin_picker_tokens.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../wallet_withdraw_coin_labels.dart';

/// A selectable asset keeps available balance and valuation visually separate.
class WalletWithdrawCoinRow extends StatelessWidget {
  const WalletWithdrawCoinRow({
    super.key,
    required this.coin,
    required this.onTap,
  });

  final CoinDto coin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final code = WalletWithdrawCoinLabels.code(coin);
    final labels = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(code,
            style: TextStyle(
                fontSize: WalletCoinPickerTokens.codeFont,
                fontWeight: FontWeight.w600,
                color: colors.text)),
        const SizedBox(height: AppTokens.s2),
        Text(WalletWithdrawCoinLabels.name(coin, i18n),
            style: TextStyle(
                fontSize: WalletCoinPickerTokens.nameFont,
                color: colors.subText)),
      ],
    );
    final balance = Semantics(
      label: i18n.t(
          zhHans: '可用余额',
          zhHant: '可用餘額',
          en: 'Available balance',
          ja: '利用可能残高',
          ko: '사용 가능한 잔액'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(coin.bal,
              style: TextStyle(
                  fontSize: WalletCoinPickerTokens.bodyFont,
                  fontWeight: FontWeight.w600,
                  color: colors.text)),
          const SizedBox(height: AppTokens.s2),
          Text(coin.fiat,
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize: WalletCoinPickerTokens.nameFont,
                  color: colors.subText)),
        ],
      ),
    );
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: WalletCoinPickerTokens.rowMinHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s5, vertical: AppTokens.s4),
            child: LayoutBuilder(builder: (context, constraints) {
              final stack = constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context)
                          .scale(WalletCoinPickerTokens.bodyFont) >
                      WalletCoinPickerTokens.bodyFont * 1.3;
              return Row(
                children: [
                  WalletCoinLogo(type: coin.type, logoUrl: coin.logoUrl),
                  const SizedBox(width: AppTokens.s4),
                  if (stack)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          labels,
                          const SizedBox(height: AppTokens.s3),
                          balance,
                        ],
                      ),
                    )
                  else ...[
                    Expanded(child: labels),
                    const SizedBox(width: AppTokens.s3),
                    Expanded(child: balance),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
