import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'payment_strings.dart';
import 'payment_sheet_tokens.dart';

/// Shared masked presentation for six-digit transaction password input.
class TradePasswordPinCells extends StatelessWidget {
  const TradePasswordPinCells({
    super.key,
    required this.length,
    required this.hasError,
    this.showEmptyDots = true,
    this.borderColor,
    this.walletPayStyle = false,
  });

  final int length;
  final bool hasError;
  final bool showEmptyDots;
  final Color? borderColor;
  final bool walletPayStyle;

  @override
  Widget build(BuildContext context) {
    final dark = (Theme.of(context).brightness == Brightness.dark);
    final border = hasError
        ? AppTokens.paymentError(dark: dark)
        : borderColor ?? AppTokens.border(dark: dark);
    return Semantics(
      label: paymentText(context, zh: '六位交易密码', en: 'Six-digit password'),
      value: paymentText(
        context,
        zh: '已输入 $length 位，共 6 位',
        en: '$length of 6 digits entered',
      ),
      liveRegion: true,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // PayPasswordPrompt's 58.w cells and 14.w total horizontal padding,
          // normalized from the reference's 750-wide design.
          final gap = walletPayStyle
              ? PaymentSheetTokens.cellGap
              : TradePasswordTokens.cellGap;
          final maxSize = walletPayStyle
              ? PaymentSheetTokens.cellSize
              : TradePasswordTokens.cellMaxSize;
          final cellSize =
              ((constraints.maxWidth - gap * (walletPayStyle ? 6 : 5)) / 6)
                  .clamp(0.0, maxSize);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 6; i++) ...[
                if (i > 0 || walletPayStyle)
                  SizedBox(width: walletPayStyle && i == 0 ? gap / 2 : gap),
                AnimatedContainer(
                  key: ValueKey('trade-password-cell-$i'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : TradePasswordTokens.inputAnimation,
                  width: cellSize,
                  height: cellSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: walletPayStyle
                        ? AppTokens.surfaceAlt(dark: dark)
                        : null,
                    borderRadius: BorderRadius.circular(walletPayStyle
                        ? PaymentSheetTokens.cellRadius
                        : AppTokens.rSm),
                    border: Border.all(
                        color: border, width: walletPayStyle ? .5 : 1),
                  ),
                  child: Container(
                    key: ValueKey('trade-password-dot-$i'),
                    width: walletPayStyle
                        ? PaymentSheetTokens.cellDot
                        : TradePasswordTokens.dotSize,
                    height: walletPayStyle
                        ? PaymentSheetTokens.cellDot
                        : TradePasswordTokens.dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: length > i
                          ? AppTokens.textPrimary(dark: dark)
                          : showEmptyDots
                              ? AppTokens.border(dark: dark)
                              : AppTokens.border(dark: dark)
                                  .withValues(alpha: 0),
                    ),
                  ),
                ),
              ],
              if (walletPayStyle) SizedBox(width: gap / 2),
            ],
          );
        },
      ),
    );
  }
}
