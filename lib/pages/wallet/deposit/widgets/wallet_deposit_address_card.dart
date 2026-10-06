import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_deposit_tokens.dart';

/// Network and address details for an allocated address, without the QR.
class WalletDepositAddressCard extends StatelessWidget {
  const WalletDepositAddressCard({
    super.key,
    required this.address,
    required this.currency,
    required this.onCopy,
    this.onNetworkInfo,
  });

  final WalletDepositAddress address;
  final FundCurrency currency;
  final VoidCallback onCopy;
  final VoidCallback? onNetworkInfo;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final labelStyle = TextStyle(
      fontSize: WalletDepositTokens.detailText,
      fontWeight: FontWeight.w600,
      color: colors.text,
    );
    return Material(
      key: const ValueKey('wallet-deposit-ready'),
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppTokens.rCard),
      child: Padding(
        key: const ValueKey('wallet-deposit-card'),
        padding: const EdgeInsets.all(AppTokens.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i18n.t(
                          zhHans: '网络名称',
                          zhHant: '網路名稱',
                          en: 'Network name',
                          ja: 'ネットワーク名',
                          ko: '네트워크 이름',
                        ),
                        style: labelStyle,
                      ),
                      const SizedBox(height: AppTokens.s2),
                      Text(
                        address.network == 'TRON' ? 'Tron' : address.network,
                        key: const ValueKey('wallet-deposit-network'),
                        style: TextStyle(
                          fontSize: WalletDepositTokens.body,
                          color: colors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onNetworkInfo != null)
                  _DetailInfoButton(
                    key: const ValueKey('wallet-deposit-network-info'),
                    label: i18n.t(
                      zhHans: '查看网络说明',
                      zhHant: '查看網路說明',
                      en: 'View network information',
                      ja: 'ネットワーク情報を表示',
                      ko: '네트워크 정보 보기',
                    ),
                    onPressed: onNetworkInfo!,
                  ),
              ],
            ),
            Divider(height: AppTokens.s5, color: colors.line),
            Semantics(
              button: true,
              hint: i18n.t(
                zhHans: '点击复制充值地址',
                zhHant: '點擊複製儲值地址',
                en: 'Tap to copy the deposit address',
                ja: 'タップして入金アドレスをコピー',
                ko: '탭하여 입금 주소 복사',
              ),
              child: InkWell(
                key: const ValueKey('wallet-deposit-address-copy'),
                onTap: onCopy,
                borderRadius: BorderRadius.circular(AppTokens.rMd),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: WalletDepositTokens.minTap,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          i18n.format(
                            zhHans: '{code}充值地址',
                            zhHant: '{code}儲值地址',
                            en: '{code} deposit address',
                            ja: '{code}入金アドレス',
                            ko: '{code} 입금 주소',
                            vars: {'code': currency.code},
                          ),
                          style: labelStyle,
                        ),
                        const SizedBox(height: AppTokens.s2),
                        Text(
                          address.address,
                          key: const ValueKey('wallet-deposit-address'),
                          style: TextStyle(
                            fontSize: WalletDepositTokens.body,
                            height: 1.4,
                            color: colors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailInfoButton extends StatelessWidget {
  const _DetailInfoButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        tooltip: label,
        icon: const Icon(Icons.info_outline_rounded),
        iconSize: AppTokens.s6,
        color: WalletPageColors.of(context).subText,
        padding: const EdgeInsets.all(AppTokens.s4),
        constraints: const BoxConstraints(
          minWidth: WalletDepositTokens.minTap,
          minHeight: WalletDepositTokens.minTap,
        ),
        visualDensity: VisualDensity.standard,
      );
}
