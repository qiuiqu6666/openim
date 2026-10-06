import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../host/wallet_i18n.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../wallet_record_tokens.dart';
import '../../widgets/wallet_record_amount_text.dart';
import 'wallet_journal_detail_tokens.dart';

/// A receipt row with a quiet label and a wrapping, left-aligned value.
class WalletJournalDetailField extends StatelessWidget {
  const WalletJournalDetailField({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    this.copy = false,
    this.amount = false,
    this.valueColor,
    this.onTap,
  });

  final String id;
  final String label;
  final String value;
  final bool copy;
  final bool amount;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final labelWidget = Text(label,
        style: TextStyle(
            color: WalletRecordTokens.muted(context),
            fontSize: WalletJournalDetailTokens.body));
    final style = TextStyle(
        color: valueColor ?? colors.text,
        fontSize: WalletJournalDetailTokens.body);
    final valueWidget = amount
        ? WalletRecordAmountText(
            value: value,
            textKey: ValueKey('wallet-journal-detail-$id'),
            textAlign: TextAlign.start,
            style: style,
          )
        : Text(
            copy
                ? value.replaceAllMapped(
                    RegExp(r'(\S)(?=\S)'), (match) => '${match[1]}\u200B')
                : value,
            key: ValueKey('wallet-journal-detail-$id'),
            semanticsLabel: value,
            style: style,
          );
    final copyButton = copy
        ? IconButton(
            key: ValueKey('wallet-journal-copy-$id'),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            tooltip: i18n.t(
                zhHans: '复制$label',
                zhHant: '複製$label',
                en: 'Copy $label',
                ja: '$labelをコピー',
                ko: '$label 복사'),
            style: WalletRecordTokens.iconStyle(context),
            icon: Icon(Icons.copy_rounded,
                color: colors.subText, size: AppTokens.s5),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: WalletJournalDetailTokens.rowPadding),
      child: LayoutBuilder(builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < WalletJournalDetailTokens.stackedWidth ||
                MediaQuery.textScalerOf(context)
                        .scale(WalletJournalDetailTokens.body) >
                    WalletJournalDetailTokens.stackedFont;
        final valueRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: onTap == null
                    ? valueWidget
                    : Semantics(
                        link: true,
                        child: InkWell(
                          key: ValueKey('wallet-journal-open-$id'),
                          onTap: onTap,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: valueWidget)),
                        ),
                      )),
            if (copyButton != null) copyButton,
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labelWidget,
              const SizedBox(height: AppTokens.s3),
              valueRow,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: WalletJournalDetailTokens.labelWidth,
                child: labelWidget),
            const SizedBox(width: AppTokens.s4),
            Expanded(child: valueRow),
          ],
        );
      }),
    );
  }
}
