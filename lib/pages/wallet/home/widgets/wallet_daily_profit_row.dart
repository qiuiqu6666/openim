import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../host/wallet_i18n.dart';
import '../../wallet_controller.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_home_tokens.dart';
import '../wallet_amount_display.dart';

/// Displays the server daily change; unavailable values use zero placeholders.
class WalletDailyProfitRow extends StatelessWidget {
  const WalletDailyProfitRow({super.key});

  @override
  Widget build(BuildContext context) {
    final (visible, amount, percentage) =
        context.select<WalletController, (bool, String, String)>(
            (c) => (c.showBal, c.dailyAmountCny, c.dailyPercentage));
    final colors = WalletPageColors.of(context);
    final displayedAmount = walletAmountDisplay(amount);
    final numericAmount = displayedAmount.replaceAll(RegExp(r'[¥$≈,\s]'), '');
    final valueColor = !visible || !RegExp(r'[1-9]').hasMatch(numericAmount)
        ? colors.text
        : numericAmount.startsWith('-')
            ? WalletHomeTokens.dailyDecrease(context)
            : WalletHomeTokens.dailyIncrease(context);
    final i18n = AppI18n.of(context);
    final title = i18n.t(
        zhHans: '今日变动',
        zhHant: '今日變動',
        en: "Today's P&L",
        ja: '本日の損益',
        ko: '오늘 손익');
    return ConstrainedBox(
      key: const ValueKey('wallet-daily-profit-row'),
      constraints: const BoxConstraints(minHeight: WalletHomeTokens.minTap),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: AppTokens.s2,
          runSpacing: AppTokens.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title,
                style: TextStyle(
                    color: colors.text, fontSize: WalletHomeTokens.body)),
            Text(
                visible
                    ? '$displayedAmount (${walletAmountDisplay(percentage)}%)'
                    : '••••••',
                key: const ValueKey('wallet-daily-profit'),
                style: TextStyle(
                    color: valueColor,
                    fontSize: WalletHomeTokens.body,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}
