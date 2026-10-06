import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_deposit_tokens.dart';
import 'wallet_deposit_address_card.dart';
import 'wallet_deposit_qr.dart';
import 'wallet_deposit_rule_details.dart';

/// Scrollable ready state. Address allocation and sharing stay with the screen.
class WalletDepositReadyContent extends StatelessWidget {
  const WalletDepositReadyContent({
    super.key,
    required this.address,
    required this.currency,
    required this.onCopy,
    required this.onShare,
    this.onNetworkInfo,
  });

  final WalletDepositAddress address;
  final FundCurrency currency;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onNetworkInfo;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final colors = WalletPageColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('wallet-deposit-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s5,
              AppTokens.s7,
              AppTokens.s5,
              AppTokens.s5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: WalletDepositQr(
                        address: address,
                        currency: currency,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s7),
                    WalletDepositAddressCard(
                      address: address,
                      currency: currency,
                      onCopy: onCopy,
                      onNetworkInfo: onNetworkInfo,
                    ),
                    const SizedBox(height: AppTokens.s7),
                    WalletDepositRuleDetails(
                        address: address, currency: currency),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.s7),
                  child: FilledButton(
                    key: const ValueKey('wallet-deposit-share'),
                    onPressed: onShare,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          colors.dark ? AppTokens.ink100 : AppTokens.ink900,
                      foregroundColor: colors.dark
                          ? AppTokens.ink900
                          : AppTokens.surfaceLight,
                      minimumSize: const Size(0, WalletDepositTokens.minTap),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.s5,
                        vertical: AppTokens.s4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.rMd),
                      ),
                      textStyle:
                          Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontSize: WalletDepositTokens.body,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    child: Text(
                      i18n.t(
                        zhHans: '保存并分享地址',
                        zhHant: '儲存並分享地址',
                        en: 'Save and share address',
                        ja: 'アドレスを保存して共有',
                        ko: '주소 저장 및 공유',
                      ),
                      textAlign: TextAlign.center,
                    ),
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
