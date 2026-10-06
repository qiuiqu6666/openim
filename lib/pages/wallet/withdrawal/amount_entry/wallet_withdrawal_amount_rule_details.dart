import 'package:flutter/material.dart';

import '../../data/currency_rules/wallet_withdrawal_policy.dart';
import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/currency_rules/wallet_withdrawal_policy_labels.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import 'wallet_withdrawal_rules_controller.dart';

class WalletWithdrawalAmountRuleDetails extends StatelessWidget {
  const WalletWithdrawalAmountRuleDetails({
    super.key,
    required this.controller,
    this.amount,
    this.issue,
  });

  final WalletWithdrawalRulesController controller;
  final FundAmount? amount;
  final WalletWithdrawalPolicyIssue? issue;

  @override
  Widget build(BuildContext context) {
    final labels = WalletWithdrawalPolicyLabels(AppI18n.of(context));
    final colors = WalletPageColors.of(context);
    final rule = controller.rule;
    final style =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.subText);
    final total = rule?.isWithdrawalComplete == true && amount != null
        ? WalletWithdrawalPolicy(rule: rule!).totalDebit(amount!)
        : null;
    return Column(
      key: const ValueKey('wallet-withdraw-entry-rules'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(labels.minimum(rule, controller.currency),
            key: const ValueKey('wallet-withdraw-entry-minimum'),
            textAlign: TextAlign.right,
            style: style),
        const SizedBox(height: AppTokens.s2),
        Text(labels.fee(rule, controller.currency),
            key: const ValueKey('wallet-withdraw-entry-fee'),
            textAlign: TextAlign.right,
            style: style),
        if (total != null) ...[
          const SizedBox(height: AppTokens.s2),
          Text(labels.total(total),
              key: const ValueKey('wallet-withdraw-entry-total'),
              textAlign: TextAlign.right,
              style: style),
        ],
        if (controller.loading) ...[
          const SizedBox(height: AppTokens.s2),
          Text(labels.loading, textAlign: TextAlign.right, style: style),
        ] else if (!controller.isCurrentAccount) ...[
          const SizedBox(height: AppTokens.s2),
          Text(labels.accountChanged,
              style: style?.copyWith(color: colors.red)),
        ] else if (controller.failed) ...[
          const SizedBox(height: AppTokens.s2),
          Text(labels.unavailable, style: style?.copyWith(color: colors.red)),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('wallet-withdraw-entry-rules-retry'),
                onPressed: controller.isActive ? controller.load : null,
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppTokens.buttonHeight)),
                child: Text(labels.retry),
              )),
        ] else if (issue != null) ...[
          const SizedBox(height: AppTokens.s2),
          Text(labels.issue(issue!, rule),
              key: const ValueKey('wallet-withdraw-entry-issue'),
              style: style?.copyWith(color: colors.red)),
        ],
      ],
    );
  }
}
