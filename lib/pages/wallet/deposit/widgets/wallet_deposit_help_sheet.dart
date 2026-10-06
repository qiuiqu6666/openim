import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/currency_rules/wallet_currency_rule_labels.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_deposit_tokens.dart';
import 'wallet_deposit_rule_details.dart';

/// Deposit instructions use the current network and admission threshold only.
class WalletDepositHelpSheet extends StatelessWidget {
  const WalletDepositHelpSheet({
    super.key,
    required this.currency,
    this.address,
  });

  final FundCurrency currency;
  final WalletDepositAddress? address;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final labels = WalletCurrencyRuleLabels(i18n);
    final rule = address?.ruleFor(currency);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: WalletDepositTokens.maxWidth,
            maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Material(
          key: const ValueKey('wallet-deposit-help-sheet'),
          color: colors.card,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rCard)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      i18n.t(
                          zhHans: '充值须知',
                          zhHant: '儲值須知',
                          en: 'Deposit information',
                          ja: '入金について',
                          ko: '입금 안내'),
                      style: TextStyle(
                          color: colors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: i18n.t(
                        zhHans: '关闭',
                        zhHant: '關閉',
                        en: 'Close',
                        ja: '閉じる',
                        ko: '닫기'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: AppTokens.s5),
                Text(
                  address == null
                      ? i18n.t(
                          zhHans: '充值地址生成后，可查看网络和充值地址。',
                          zhHant: '儲值地址產生後，可查看網路和儲值地址。',
                          en:
                              'The network and deposit address appear when ready.',
                          ja: '生成後にネットワークと入金アドレスを確認できます。',
                          ko: '주소가 생성되면 네트워크와 입금 주소를 확인할 수 있습니다.')
                      : i18n.format(
                          zhHans:
                              '请使用 {network} 网络充值 {coin}，转账前核对币种、网络和地址。{memo}',
                          zhHant:
                              '請使用 {network} 網路儲值 {coin}，轉帳前核對幣種、網路和地址。{memo}',
                          en: 'Deposit {coin} on {network}. Check the coin, network and address before sending. {memo}',
                          ja: '{network}で{coin}を入金してください。送金前に通貨、ネットワーク、アドレスを確認してください。{memo}',
                          ko: '{network} 네트워크로 {coin}을 입금하세요. 전송 전에 코인, 네트워크, 주소를 확인하세요. {memo}',
                          vars: {
                              'network': address!.network,
                              'coin': currency.code,
                              'memo': labels.memoHint(rule?.memoRequired),
                            }),
                  style:
                      TextStyle(fontSize: 15, color: colors.text, height: 1.6),
                ),
                if (address != null) ...[
                  const SizedBox(height: AppTokens.s5),
                  WalletDepositRuleDetails(
                    address: address!,
                    currency: currency,
                    includeConfirmation: false,
                    includeNotice: false,
                    keyPrefix: 'wallet-deposit-help',
                  ),
                  const SizedBox(height: AppTokens.s5),
                  Text(
                    i18n.format(
                        zhHans: '充值入账需要 {count} 次区块确认。网络异常时到账可能延迟，区块回滚可能撤销入账。',
                        zhHant: '儲值入帳需要 {count} 次區塊確認。網路異常時到帳可能延遲，區塊回滾可能撤銷入帳。',
                        en: 'Deposits require {count} block confirmations. Network issues may delay processing; block reorganizations may reverse credits.',
                        ja: '入金には{count}回のブロック承認が必要です。ネットワーク障害で反映が遅れたり、ブロックの巻き戻しで取り消される場合があります。',
                        ko: '입금에는 블록 확인 {count}회가 필요합니다. 네트워크 문제로 처리가 지연되거나 블록 재구성으로 입금이 취소될 수 있습니다.',
                        vars: {'count': address!.confirmations}),
                    style: TextStyle(
                        fontSize: 14, color: colors.subText, height: 1.6),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
