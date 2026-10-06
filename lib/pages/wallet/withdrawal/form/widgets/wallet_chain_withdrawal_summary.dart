import 'package:flutter/material.dart';

import '../../../data/wallet_fund_api.dart';
import '../../../host/wallet_i18n.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../wallet_chain_withdrawal_labels.dart';
import '../wallet_chain_withdrawal_tokens.dart';

/// Displays the principal and separately charged fee without calculating them.
class WalletChainWithdrawalSummary extends StatelessWidget {
  const WalletChainWithdrawalSummary({
    super.key,
    required this.currency,
    this.received,
    this.fee,
    this.totalDebit,
    this.onFeeInfo,
  });

  final FundCurrency currency;
  final String? received;
  final String? fee;
  final String? totalDebit;
  final VoidCallback? onFeeInfo;

  @override
  Widget build(BuildContext context) {
    final labels = WalletChainWithdrawalLabels(AppI18n.of(context));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: AppTokens.fontFamilyOf(context),
      fontSize: WalletChainWithdrawalTokens.bodySize,
      color: AppTokens.appTextSecondary(dark),
      height: 1.5,
    );
    final valueStyle = style.copyWith(
      fontSize: WalletChainWithdrawalTokens.inputSize,
      color: AppTokens.appTextPrimary(dark),
      fontWeight: FontWeight.w500,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(labels.securityNote, style: style),
        const SizedBox(height: WalletChainWithdrawalTokens.sectionGap),
        _valueRow(
          context,
          label: labels.receivedLabel,
          value: labels.amount(received, currency),
          valueKey: const ValueKey('wallet-chain-received'),
          labelStyle: style,
          valueStyle: valueStyle,
        ),
        const SizedBox(height: WalletChainWithdrawalTokens.rowGap),
        _valueRow(
          context,
          label: labels.feeLabel,
          value: labels.amount(fee, currency),
          valueKey: const ValueKey('wallet-chain-fee'),
          labelStyle: style,
          valueStyle: valueStyle,
          onInfo: onFeeInfo,
          infoKey: const ValueKey('wallet-chain-fee-info'),
        ),
        const SizedBox(height: WalletChainWithdrawalTokens.rowGap),
        Text(
          labels.totalDebit(totalDebit, currency),
          key: const ValueKey('wallet-chain-total-debit'),
          style:
              style.copyWith(fontSize: WalletChainWithdrawalTokens.captionSize),
        ),
      ],
    );
  }

  Widget _valueRow(
    BuildContext context, {
    required String label,
    required String value,
    required Key valueKey,
    required TextStyle labelStyle,
    required TextStyle valueStyle,
    VoidCallback? onInfo,
    Key? infoKey,
  }) {
    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, style: labelStyle)),
        if (onInfo != null)
          IconButton(
            key: infoKey,
            onPressed: onInfo,
            tooltip: WalletChainWithdrawalLabels(AppI18n.of(context)).info,
            constraints: const BoxConstraints.tightFor(
              width: WalletChainWithdrawalTokens.tapSize,
              height: WalletChainWithdrawalTokens.tapSize,
            ),
            iconSize: WalletChainWithdrawalTokens.iconSize,
            color: labelStyle.color,
            icon: const Icon(Icons.info_outline),
          ),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      final stackValues = MediaQuery.textScalerOf(context)
              .scale(WalletChainWithdrawalTokens.inputSize) >=
          WalletChainWithdrawalTokens.stackedTextSize;
      if (stackValues) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelWidget,
            Text(value, key: valueKey, style: valueStyle),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: labelWidget),
          const SizedBox(width: WalletChainWithdrawalTokens.rowGap),
          Expanded(
            child: Text(value,
                key: valueKey, style: valueStyle, textAlign: TextAlign.end),
          ),
        ],
      );
    });
  }
}
