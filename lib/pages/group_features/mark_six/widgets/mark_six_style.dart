// Adapted from 99chat lottery_theme.dart / agent_rebate_summary_card.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
export '../models/mark_six_json.dart';

class MarkSixStyle {
  MarkSixStyle.of(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get background => AppTokens.background(dark: dark);
  Color get surface => AppTokens.surface(dark: dark);
  Color get alternate => AppTokens.surfaceAlt(dark: dark);
  Color get text => AppTokens.textPrimary(dark: dark);
  Color get secondary => AppTokens.textSecondary(dark: dark);
  Color get divider => AppTokens.border(dark: dark);
  Color get primary => const Color(0xFF007AFF);
  Color get error => AppTokens.paymentError(dark: dark);
  Color get lotteryBackground => dark ? background : const Color(0xFFF3F8FF);
  Color get lotteryPanel => dark ? surface : const Color(0xFFFAFCFF);
  Color get lotteryAlt => dark ? alternate : const Color(0xFFF0F6FF);
  Color get lotteryBorder => dark ? divider : const Color(0xFFD8E6FC);
  Color get declarationText => dark ? text : const Color(0xFF17243D);
  Color get declarationAlt => dark ? alternate : const Color(0xFFF2F8FF);
  Color get declarationBorder => dark ? alternate : const Color(0xFFE7EDF5);
  Color get declarationDivider => dark ? divider : const Color(0xFFE5EEFC);
  Color get declarationMuted => dark ? secondary : const Color(0xFF8291A8);
  Color get declarationQuote =>
      dark ? const Color(0xFF34506E) : const Color(0xFFDDEBFF);
  Color get declarationCopyIcon => dark ? secondary : const Color(0xFF6B84A8);
  Color get declarationFooter => dark ? secondary : const Color(0xFF8B9BB2);
  Color get declarationRule => dark ? divider : const Color(0xFFB7C9E4);
  static const declarationShadow = [
    BoxShadow(color: Color(0x050F274D), blurRadius: 12, offset: Offset(0, 3))
  ];
  static const radius = 16.0;
  static const inset = 16.0;
  static const red = Color(0xFFEF2F4E);
  static const blue = Color(0xFF007AFF);
  static const green = Color(0xFF00B25E);
  static const shadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 2))
  ];
}

class MarkSixEmpty extends StatelessWidget {
  const MarkSixEmpty(
      {super.key, required this.message, this.onRetry, this.compact = false});
  final String message;
  final VoidCallback? onRetry;
  final bool compact;
  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.all(compact ? 12 : 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!compact) ...[
              Icon(onRetry == null ? Icons.inbox_outlined : Icons.error_outline,
                  size: 42, color: MarkSixStyle.of(context).secondary),
              const SizedBox(height: 12),
            ],
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: MarkSixStyle.of(context).secondary)),
            if (onRetry != null) ...[
              SizedBox(height: compact ? 8 : 16),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ])));
}

AppBar markSixAppBar(BuildContext context, String title,
    {List<Widget>? actions}) {
  final style = MarkSixStyle.of(context);
  return AppBar(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: style.surface,
      foregroundColor: style.text,
      leading: IconButton(
          tooltip: '返回',
          color: style.primary,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded)),
      title: Text(title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: actions);
}

String markSixAmount(dynamic value) {
  final number = value is num ? value : num.tryParse('$value');
  if (number == null || !number.isFinite) return '—';
  return number == number.roundToDouble()
      ? number.toStringAsFixed(0)
      : number.toStringAsFixed(2);
}
