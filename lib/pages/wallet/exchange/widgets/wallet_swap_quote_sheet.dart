import 'package:flutter/material.dart';

import '../../record/wallet_record_amount.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../data/wallet_swap_quote.dart';
import '../data/wallet_swap_quote_controller.dart';
import '../wallet_exchange_tokens.dart';

Future<WalletSwapQuote?> showWalletSwapQuoteSheet(
        BuildContext context, WalletSwapQuoteController quotes) =>
    showModalBottomSheet<WalletSwapQuote>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: WalletPageColors.of(context).card,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppTokens.rXl))),
      builder: (context) => _WalletSwapQuoteSheet(quotes: quotes),
    );

class _WalletSwapQuoteSheet extends StatelessWidget {
  const _WalletSwapQuoteSheet({required this.quotes});
  final WalletSwapQuoteController quotes;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: quotes,
      builder: (context, _) {
        final colors = WalletPageColors.of(context);
        final theme = Theme.of(context);
        final quote = quotes.quote;
        final valid = quotes.validQuote;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('预览闪兑',
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600, color: colors.text)),
                  const SizedBox(height: AppTokens.s7),
                  if (quote != null) ...[
                    Text('预计实得',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.subText)),
                    const SizedBox(height: AppTokens.s3),
                    Text(
                        '${walletRecordAmountTwoDecimals(quote.estimatedReceived.decimal)} ${quote.toCurrency.displayName}',
                        key: const ValueKey('wallet-swap-quote-received'),
                        style: theme.textTheme.headlineMedium?.copyWith(
                            color: colors.text, fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppTokens.s5),
                    Text(
                        '转出 ${walletRecordAmountTwoDecimals(quote.amount.decimal)} ${quote.amount.currency.displayName}',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: colors.text)),
                    const SizedBox(height: AppTokens.s5),
                  ],
                  if (quotes.loading) const LinearProgressIndicator(),
                  Text(
                      quotes.error ??
                          (valid == null
                              ? '报价已过期，请重新获取'
                              : '报价有效期为 30 秒，实得数量已包含价格调整。'),
                      key: valid == null && !quotes.loading
                          ? const ValueKey('wallet-swap-quote-expired')
                          : null,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: quotes.error != null || valid == null
                              ? colors.red
                              : colors.subText)),
                  const SizedBox(height: AppTokens.s7),
                  FilledButton(
                    key: const ValueKey('wallet-swap-quote-confirm'),
                    style: FilledButton.styleFrom(
                        minimumSize:
                            const Size.fromHeight(AppTokens.buttonHeight),
                        backgroundColor: WalletExchangeTokens.action(context),
                        foregroundColor:
                            WalletExchangeTokens.onAction(context)),
                    onPressed: valid == null || quotes.loading
                        ? null
                        : () {
                            final current = quotes.validQuote;
                            if (current != null) {
                              Navigator.of(context).pop(current);
                            }
                          },
                    child: const Text('确认兑换'),
                  ),
                  if (valid == null)
                    TextButton(
                      key: const ValueKey('wallet-swap-quote-refresh'),
                      onPressed: quotes.loading ? null : quotes.refresh,
                      child: const Text('重新获取报价'),
                    ),
                ],
              ),
            ),
          ),
        );
      });
}
