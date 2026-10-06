import 'package:flutter/material.dart';
import '../data/wallet_operation_coordinator.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';
import 'form/wallet_chain_withdrawal_tokens.dart';

class WalletWithdrawalSuccessScreen extends StatelessWidget {
  const WalletWithdrawalSuccessScreen({super.key, required this.receipt});
  final WalletOperationReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return Scaffold(
      backgroundColor: colors.card,
      appBar: AppBar(
          backgroundColor: colors.card,
          foregroundColor: colors.text,
          title: const Text('提现结果')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: Column(children: [
            Expanded(
                child: Center(
                    child: SingleChildScrollView(
                        child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppTokens.success, size: AppTokens.s10),
                const SizedBox(height: AppTokens.s7),
                Text('提现申请成功',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: colors.text)),
                const SizedBox(height: AppTokens.s5),
                Text(receipt.description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: colors.subText)),
              ],
            )))),
            SizedBox(
                width: double.infinity,
                height: WalletChainWithdrawalTokens.tapSize,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'))),
          ]),
        ),
      ),
    );
  }
}
