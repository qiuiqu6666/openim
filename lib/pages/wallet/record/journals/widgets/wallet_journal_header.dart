import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../host/wallet_navigation.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../wallet_record_tokens.dart';

/// Centered journal title with no filter or customer-service actions.
class WalletJournalAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const WalletJournalAppBar._({
    required this.title,
    required this.titleStyle,
    required this.titleLines,
    required this.toolbarHeight,
  });

  factory WalletJournalAppBar.forContext(
    BuildContext context, {
    String? coin,
  }) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final title = coin == null
        ? i18n.t(
            zhHans: '历史记录', zhHant: '歷史記錄', en: 'History', ja: '履歴', ko: '기록')
        : i18n.t(
            zhHans: '$coin变动',
            zhHant: '$coin變動',
            en: '$coin changes',
            ja: '$coinの変動',
            ko: '$coin 변동');
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(
        fontSize: WalletRecordTokens.title,
        fontWeight: FontWeight.w600,
        color: colors.text);
    final width = MediaQuery.sizeOf(context).width;
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final titleWidth = width - kToolbarHeight * 2 - AppTokens.s5 * 2;
    painter.layout(maxWidth: math.max(1, titleWidth));
    final height = math.max(kToolbarHeight, painter.height + AppTokens.s4 * 2);
    final titleLines = painter.computeLineMetrics().length;
    painter.dispose();
    return WalletJournalAppBar._(
      title: title,
      titleStyle: style,
      titleLines: titleLines,
      toolbarHeight: height,
    );
  }

  final String title;
  final TextStyle titleStyle;
  final int titleLines;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return AppBar(
      leading: const AppBackButton(),
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.card,
      foregroundColor: colors.text,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: toolbarHeight,
      title: Text(title,
          key: const ValueKey('wallet-journal-list-title'),
          textAlign: TextAlign.center,
          maxLines: titleLines,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: titleStyle),
    );
  }
}
