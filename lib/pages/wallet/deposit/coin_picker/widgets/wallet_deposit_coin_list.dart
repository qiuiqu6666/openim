import 'package:flutter/material.dart';
import 'package:openim/services/fund_models.dart' show FundCurrency;

import '../../../home/wallet_home_tokens.dart';
import '../../../widgets/wallet_coin_logo.dart';
import '../../../wallet_repository.dart' show CoinType;
import '../../../widgets/coin_picker/wallet_coin_picker_list.dart';
import '../../../widgets/coin_picker/wallet_coin_picker_tokens.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../wallet_deposit_coin.dart';

/// Adapts deposit currencies to the shared picker without owning requests.
class WalletDepositCoinList extends StatelessWidget {
  const WalletDepositCoinList({
    super.key,
    required this.coins,
    required this.onSelected,
    this.searching = false,
  });

  final List<WalletDepositCoin> coins;
  final ValueChanged<FundCurrency> onSelected;
  final bool searching;

  @override
  Widget build(BuildContext context) => WalletCoinPickerList<WalletDepositCoin>(
        items: coins,
        codeOf: (coin) => coin.code,
        keyPrefix: 'wallet-deposit-coin',
        searching: searching,
        rowBuilder: (coin) => _CoinRow(
          coin: coin,
          onTap: () => onSelected(coin.currency),
        ),
      );
}

class _CoinRow extends StatelessWidget {
  const _CoinRow({required this.coin, required this.onTap});

  final WalletDepositCoin coin;
  final VoidCallback onTap;

  CoinType get _type => switch (coin.currency) {
        FundCurrency.usdt => CoinType.usdt,
        FundCurrency.trx => CoinType.trx,
        FundCurrency.bi99 => CoinType.cny,
      };

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
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
            child: Row(
              children: [
                WalletCoinLogo(type: _type, size: WalletHomeTokens.coinLogo),
                const SizedBox(width: AppTokens.s4),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(coin.code,
                          style: TextStyle(
                              fontSize: WalletCoinPickerTokens.codeFont,
                              fontWeight: FontWeight.w600,
                              color: colors.text)),
                      const SizedBox(height: AppTokens.s2),
                      Text(coin.name,
                          style: TextStyle(
                              fontSize: WalletCoinPickerTokens.nameFont,
                              color: colors.subText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
