import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/currency_rules/wallet_currency_rule_labels.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_deposit_tokens.dart';

/// Displays endpoint-provided admission rules for the selected deposit coin.
class WalletDepositRuleDetails extends StatelessWidget {
  const WalletDepositRuleDetails({
    super.key,
    required this.address,
    required this.currency,
    this.includeConfirmation = true,
    this.includeNotice = true,
    this.keyPrefix = 'wallet-deposit',
  });

  final WalletDepositAddress address;
  final FundCurrency currency;
  final bool includeConfirmation;
  final bool includeNotice;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final labels = WalletCurrencyRuleLabels(i18n);
    final rule = address.ruleFor(currency);
    final rows = <Widget>[
      _ExplanationRow(
        key: ValueKey('$keyPrefix-destination'),
        label: i18n.t(
          zhHans: '入账账户',
          zhHant: '入帳帳戶',
          en: 'Receiving account',
          ja: '入金先アカウント',
          ko: '입금 계정',
        ),
        value: labels.receivingAccount(rule?.receivingAccountType),
      ),
      _ExplanationRow(
        key: ValueKey('$keyPrefix-minimum'),
        label: i18n.t(
          zhHans: '最小充值数量',
          zhHant: '最小儲值數量',
          en: 'Minimum deposit amount',
          ja: '最小入金数量',
          ko: '최소 입금 수량',
        ),
        value: labels.amount(rule?.minDepositAmount, currency),
      ),
      _ExplanationRow(
        key: ValueKey('$keyPrefix-arrival-time'),
        label: i18n.t(
          zhHans: '充值到账时间',
          zhHant: '儲值到帳時間',
          en: 'Deposit arrival time',
          ja: '入金反映時間',
          ko: '입금 반영 시간',
        ),
        value: labels.arrival(rule?.estimatedArrivalSeconds),
      ),
      if (includeConfirmation)
        _ExplanationRow(
          key: ValueKey('$keyPrefix-confirmations'),
          label: i18n.t(
            zhHans: '充值到账',
            zhHant: '儲值到帳',
            en: 'Deposit confirmation',
            ja: '入金の承認',
            ko: '입금 확인',
          ),
          value: i18n.format(
            zhHans: '{count} 个区块确认',
            zhHant: '{count} 個區塊確認',
            en: '{count} block confirmations',
            ja: '{count}ブロックの承認',
            ko: '{count}개 블록 확인',
            vars: {'count': address.confirmations},
          ),
        ),
      _ExplanationRow(
        key: ValueKey('$keyPrefix-withdrawal-unlock'),
        label: i18n.t(
          zhHans: '提币解锁',
          zhHant: '提幣解鎖',
          en: 'Withdrawal unlock',
          ja: '出金ロック解除',
          ko: '출금 잠금 해제',
        ),
        value: labels.unlockConfirmations(rule?.withdrawUnlockConfirmations),
      ),
      if (includeNotice)
        _ExplanationRow(
          key: ValueKey('$keyPrefix-notice'),
          label: i18n.t(
            zhHans: '充值须知',
            zhHant: '儲值須知',
            en: 'Deposit notice',
            ja: '入金に関する注意事項',
            ko: '입금 안내',
          ),
          value: i18n.format(
            zhHans: '仅支持 {code}，网络 {network}。{memo}',
            zhHant: '僅支援 {code}，網路 {network}。{memo}',
            en: 'Only {code} on {network}. {memo}',
            ja: '{network}の{code}のみ対応。{memo}',
            ko: '{network}의 {code}만 지원합니다. {memo}',
            vars: {
              'code': currency.code,
              'network': address.network,
              'memo': labels.memoHint(rule?.memoRequired),
            },
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: AppTokens.s4),
          rows[index],
        ],
      ],
    );
  }
}

class _ExplanationRow extends StatelessWidget {
  const _ExplanationRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final labelStyle = TextStyle(
      fontSize: WalletDepositTokens.detailText,
      height: 1.4,
      color: colors.subText,
    );
    final valueStyle = labelStyle.copyWith(color: colors.text);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context)
                    .scale(WalletDepositTokens.detailText) >
                WalletDepositTokens.detailText * 1.3;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(height: AppTokens.s2),
              Text(value, style: valueStyle),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            const SizedBox(width: AppTokens.s5),
            Expanded(
              child: Text(value, style: valueStyle, textAlign: TextAlign.right),
            ),
          ],
        );
      },
    );
  }
}
