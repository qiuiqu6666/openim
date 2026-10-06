import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_exchange_tokens.dart';

class WalletExchangeAmount extends StatefulWidget {
  const WalletExchangeAmount(
      {super.key,
      required this.controller,
      required this.currency,
      required this.locked,
      this.inputValueUsd});
  final TextEditingController controller;
  final FundCurrency currency;
  final bool locked;
  final String? inputValueUsd;

  @override
  State<WalletExchangeAmount> createState() => _WalletExchangeAmountState();
}

class _WalletExchangeAmountState extends State<WalletExchangeAmount> {
  final _scroll = ScrollController();
  bool _showScrollHint = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_followInput);
    _followInput();
  }

  @override
  void didUpdateWidget(covariant WalletExchangeAmount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_followInput);
      widget.controller.addListener(_followInput);
    }
    _followInput();
  }

  void _followInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        final overflow = _scroll.position.maxScrollExtent > 0;
        if (_showScrollHint != overflow) {
          setState(() => _showScrollHint = overflow);
        }
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_followInput);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final theme = Theme.of(context);
    final accent = WalletExchangeTokens.estimate(context);
    final baseStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontSize: WalletExchangeTokens.amountFont,
      height: WalletExchangeTokens.amountLineHeight,
      fontWeight: FontWeight.w500,
      color: colors.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final number = value.text.isEmpty ? '0' : value.text;
        final isZero = !RegExp('[1-9]').hasMatch(number);
        return Semantics(
          key: const ValueKey('wallet-swap-amount'),
          label: '转出数量',
          value: '$number ${widget.currency.displayName}',
          readOnly: widget.locked,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('兑换数量',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: colors.subText)),
            const SizedBox(height: AppTokens.s3),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: LayoutBuilder(builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(text: number, style: baseStyle),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final width = (constraints.maxWidth -
                        AppTokens.s3 -
                        WalletExchangeTokens.caretWidth)
                    .clamp(1.0, double.infinity);
                final size =
                    (WalletExchangeTokens.amountFont * width / painter.width)
                        .clamp(WalletExchangeTokens.amountMinFont,
                            WalletExchangeTokens.amountFont);
                painter.dispose();
                final style = baseStyle.copyWith(fontSize: size);
                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    key: const ValueKey('wallet-swap-amount-scroll'),
                    scrollDirection: Axis.horizontal,
                    controller: _scroll,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(number,
                          key: const ValueKey('wallet-swap-amount-text'),
                          style: style),
                      const SizedBox(width: AppTokens.s2),
                      SizedBox(
                          width: WalletExchangeTokens.caretWidth,
                          height: MediaQuery.textScalerOf(context).scale(size),
                          child: ColoredBox(
                              color: widget.locked ? colors.line : accent)),
                    ]),
                  ),
                );
              })),
              const SizedBox(width: AppTokens.s4),
              Text(widget.currency.displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: WalletExchangeTokens.currencyFont,
                      fontWeight: FontWeight.w600,
                      color: colors.subText)),
            ]),
            const SizedBox(height: AppTokens.s3),
            Text(isZero ? '≈0.00 USD' : '≈ ${widget.inputValueUsd ?? '--'} USD',
                key: const ValueKey('wallet-swap-fiat'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: accent)),
            if (_showScrollHint) ...[
              const SizedBox(height: AppTokens.s2),
              Text('左右滑动查看完整数量',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.subText)),
            ],
          ]),
        );
      },
    );
  }
}
