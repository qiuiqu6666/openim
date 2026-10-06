import 'package:flutter/material.dart';

import '../../../data/currency_rules/wallet_withdrawal_policy.dart';
import '../../../data/wallet_fund_api.dart';
import '../../../host/wallet_i18n.dart';
import '../../widgets/wallet_withdrawal_pending_actions.dart';
import '../../../widgets/currency_rules/wallet_withdrawal_policy_labels.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../wallet_chain_withdrawal_controller.dart';
import '../wallet_chain_withdrawal_labels.dart';
import '../wallet_chain_withdrawal_tokens.dart';
import 'wallet_chain_withdrawal_fields.dart';
import 'wallet_chain_withdrawal_summary.dart';

/// Presentation for one-page withdrawal; actions and ownership remain outside.
class WalletChainWithdrawalBody extends StatelessWidget {
  const WalletChainWithdrawalBody({
    super.key,
    required this.controller,
    required this.formKey,
    required this.addressController,
    required this.amountController,
    required this.editable,
    required this.authorizing,
    required this.picking,
    required this.onAddressChanged,
    required this.onAmountChanged,
    required this.onPaste,
    required this.onScan,
    required this.onNetwork,
    required this.onAll,
    required this.onInfo,
    required this.onQuery,
    required this.onSubmit,
    this.actionError,
  });

  final WalletChainWithdrawalController controller;
  final GlobalKey<FormState> formKey;
  final TextEditingController addressController, amountController;
  final bool editable, authorizing, picking;
  final String? actionError;
  final ValueChanged<String> onAddressChanged, onAmountChanged;
  final VoidCallback onPaste,
      onScan,
      onNetwork,
      onAll,
      onQuery,
      onSubmit;
  final void Function(String title, String message) onInfo;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final labels = WalletChainWithdrawalLabels(AppI18n.of(context));
    final policyLabels = WalletWithdrawalPolicyLabels(AppI18n.of(context));
    final currency = controller.currency;
    final amount = controller.amount;
    final operation = controller.operation;
    final issue = controller.policyIssue;
    final current = controller.isCurrentAccount;
    final addressError = controller.address.isEmpty
        ? null
        : controller.isSelfAddress
            ? labels.selfAddress
            : !controller.addressValid
                ? labels.addressInvalid
                : null;
    final amountError = controller.amountText.isEmpty
        ? null
        : amount?.isPositive != true
            ? labels.invalidAmount
            : issue != null && issue != WalletWithdrawalPolicyIssue.incomplete
                ? policyLabels.issue(issue, controller.rule)
                : null;
    final fee = operation.receipt?.fee ??
        operation.receipt?.order.fee ??
        (operation.draft?.submitted == true || !controller.networkSelected
            ? null
            : controller.rule?.withdrawFee);
    String? total;
    if (amount != null && fee != null) {
      try {
        total = WalletWithdrawalPolicy.addFee(
                amount, FundAmount.parse(fee, currency))
            .decimal;
      } on FormatException {
        // Unknown or invalid fees remain unknown, never default to zero.
      }
    }
    final error = !current
        ? labels.accountChanged
        : currency == FundCurrency.bi99
            ? labels.unsupported
            : actionError ??
                (controller.failed
                    ? controller.error ?? policyLabels.unavailable
                    : null);
    return SafeArea(
        top: false,
        child: Stack(fit: StackFit.expand, children: [
          Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: WalletChainWithdrawalTokens.maxWidth),
            child: SingleChildScrollView(
              key: const ValueKey('wallet-chain-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding:
                  const EdgeInsets.all(WalletChainWithdrawalTokens.pagePadding),
              child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (current) ...[
                        WalletChainWithdrawalFields(
                          currency: currency,
                          addressController: addressController,
                          amountController: amountController,
                          enabled: editable,
                          networkSelected: controller.networkSelected,
                          network: controller.network,
                          minimum: controller.rule?.minWithdrawAmount,
                          balanceText:
                              controller.balance?.available.displayDecimal,
                          addressError: addressError,
                          amountError: amountError,
                          onAddressChanged: onAddressChanged,
                          onAmountChanged: onAmountChanged,
                          onPaste: editable ? onPaste : null,
                          onScan: editable ? onScan : null,
                          onNetwork: editable && controller.network != null
                              ? onNetwork
                              : null,
                          onAll: editable &&
                                  controller.rule?.isWithdrawalComplete == true
                              ? onAll
                              : null,
                          onAddressInfo: () =>
                              onInfo(labels.address, labels.addressNote),
                          onNetworkInfo: () =>
                              onInfo(labels.networkLabel, labels.networkNote),
                          onAmountInfo: () =>
                              onInfo(labels.quantity, labels.amountNote),
                        ),
                        Divider(
                            height: WalletChainWithdrawalTokens.sectionGap,
                            color: AppTokens.appBorder(colors.dark)),
                        WalletChainWithdrawalSummary(
                            currency: currency,
                            received: amount?.isPositive == true
                                ? amount!.decimal
                                : null,
                            fee: fee,
                            totalDebit: total,
                            onFeeInfo: () =>
                                onInfo(labels.feeLabel, labels.feeNote)),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: AppTokens.s5),
                        Text(error,
                            key: const ValueKey('wallet-chain-error'),
                            style: TextStyle(color: colors.red)),
                        if (current)
                          TextButton(
                              key: const ValueKey('wallet-chain-retry'),
                              onPressed: controller.loading || authorizing
                                  ? null
                                  : controller.load,
                              child: Text(labels.retry)),
                      ],
                      if (current &&
                          (operation.draft?.submitted == true ||
                              operation.receipt != null)) ...[
                        const SizedBox(height: AppTokens.s5),
                        WalletWithdrawalPendingActions(
                            coordinator: operation,
                            onQuery: onQuery),
                      ],
                      const SizedBox(height: AppTokens.s5),
                      FilledButton(
                          key: const ValueKey('wallet-chain-submit'),
                          style: FilledButton.styleFrom(
                              minimumSize:
                                  const Size.fromHeight(AppTokens.buttonHeight),
                              backgroundColor: colors.blue,
                              foregroundColor:
                                  WalletChainWithdrawalTokens.buttonForeground,
                              disabledBackgroundColor: colors.disabledButton,
                              disabledForegroundColor:
                                  WalletChainWithdrawalTokens.buttonForeground,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      WalletChainWithdrawalTokens
                                          .buttonRadius))),
                          onPressed:
                              !authorizing && !picking && controller.canSubmit
                                  ? onSubmit
                                  : null,
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTokens.s3),
                              child: Text(authorizing || operation.busy
                                  ? labels.loading
                                  : labels.withdraw))),
                    ],
                  )),
            ),
          )),
          if (current && controller.loading)
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxWidth: WalletChainWithdrawalTokens.maxWidth),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: WalletChainWithdrawalTokens
                                        .pagePadding),
                                child: LinearProgressIndicator(
                                    key: const ValueKey('wallet-chain-loading'),
                                    color: colors.blue)))))),
        ]));
  }
}
