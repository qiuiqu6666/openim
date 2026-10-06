import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/currency_rules/wallet_withdrawal_policy_labels.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../wallet_withdrawal_review_labels.dart';

/// Exact values from the current policy, with submitted fees taking precedence.
class WalletWithdrawalRuleSummary extends StatelessWidget {
  const WalletWithdrawalRuleSummary({
    super.key,
    required this.currency,
    required this.rule,
    required this.fee,
    required this.totalDebit,
  });

  final FundCurrency currency;
  final WalletCurrencyRule? rule;
  final String? fee;
  final FundAmount? totalDebit;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final labels = WalletWithdrawalReviewLabels(i18n);
    final policy = WalletWithdrawalPolicyLabels(i18n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(policy.minimum(rule, currency),
            key: const ValueKey('wallet-withdraw-minimum')),
        const SizedBox(height: AppTokens.s3),
        Text(policy.feeAmount(fee, currency),
            key: const ValueKey('wallet-withdraw-fee')),
        const SizedBox(height: AppTokens.s3),
        Text(policy.totalAmount(totalDebit, currency),
            key: const ValueKey('wallet-withdraw-total-debit')),
        const SizedBox(height: AppTokens.s3),
        Text(labels.feeExplanation),
      ],
    );
  }
}
