import 'package:flutter/material.dart';

import '../../widgets/wallet_99chat_tokens.dart';
import '../wallet_exchange_tokens.dart';

/// Keep quantity entry and the primary action within reach on regular phones.
/// Short screens and large text retain a single scrollable reading order.
class WalletExchangeLayout extends StatelessWidget {
  const WalletExchangeLayout({
    super.key,
    required this.amount,
    required this.form,
    required this.button,
    required this.keypad,
    required this.status,
    this.feedback,
    this.loading = false,
  });

  final Widget amount, form, button, keypad, status;
  final Widget? feedback;
  final bool loading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final scrollAll = constraints.maxHeight <
                  WalletExchangeTokens.fixedFooterMinHeight ||
              textScale > WalletExchangeTokens.footerTextScaleLimit;
          final gutter =
              constraints.maxWidth < 360 ? AppTokens.s5 : AppTokens.s7;
          final content = Padding(
            padding:
                EdgeInsets.fromLTRB(gutter, AppTokens.s7, gutter, AppTokens.s7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                amount,
                const SizedBox(height: AppTokens.s7),
                form,
                if (feedback != null) ...[
                  const SizedBox(height: AppTokens.s3),
                  feedback!,
                ],
                const SizedBox(height: AppTokens.s5),
                status,
              ],
            ),
          );
          final footer = Padding(
            key: const ValueKey('wallet-swap-entry-footer'),
            padding:
                EdgeInsets.fromLTRB(gutter, AppTokens.s3, gutter, AppTokens.s3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [button, const SizedBox(height: AppTokens.s3), keypad],
            ),
          );
          return Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: WalletExchangeTokens.maxWidth),
              child: scrollAll
                  ? SingleChildScrollView(
                      child: Column(children: [
                        if (loading) const LinearProgressIndicator(),
                        content,
                        footer,
                      ]),
                    )
                  : Column(children: [
                      if (loading) const LinearProgressIndicator(),
                      Expanded(
                        child: LayoutBuilder(
                            builder: (context, upper) => SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minHeight: upper.maxHeight),
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [content]),
                                  ),
                                )),
                      ),
                      footer,
                    ]),
            ),
          );
        },
      );
}
