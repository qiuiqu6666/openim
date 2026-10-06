import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../filters/wallet_record_filters.dart';
import '../../wallet_record_tokens.dart';
import '../wallet_journal_filter_options.dart';

typedef WalletJournalOptionBuilder = Widget Function(
    String key, String label, bool selected, VoidCallback onPressed);

class WalletJournalFilterSections extends StatelessWidget {
  const WalletJournalFilterSections(
      {super.key,
      required this.selection,
      required this.onChanged,
      required this.optionBuilder,
      this.fixedBizType});
  final WalletRecordSelection selection;
  final ValueChanged<WalletRecordSelection> onChanged;
  final WalletJournalOptionBuilder optionBuilder;
  final String? fixedBizType;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final bizType = fixedBizType ?? selection.journalBizType;
    final types = bizType == null
        ? walletJournalBizTypes.values.expand((types) => types).toSet()
        : (walletJournalBizTypes[bizType] ?? const <String>[]).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (fixedBizType == null) ...[
        _section(
            context,
            i18n.t(
                zhHans: '业务类型',
                zhHant: '業務類型',
                en: 'Business',
                ja: '取引種類',
                ko: '거래 종류'),
            [
              for (final value in ['all', ...walletJournalBizTypes.keys])
                optionBuilder(
                    'wallet-journal-biz-$value',
                    walletJournalFilterLabel(value, i18n),
                    value == (selection.journalBizType ?? 'all'),
                    () => onChanged(selection.copyWith(
                        journalBizType: value,
                        clearJournalBizType: value == 'all',
                        clearJournalType: true))),
            ]),
        const SizedBox(height: AppTokens.s7),
      ],
      _section(
          context,
          i18n.t(
              zhHans: '明细类型',
              zhHant: '明細類型',
              en: 'Event type',
              ja: '明細種類',
              ko: '내역 종류'),
          [
            for (final value in ['all', ...types])
              optionBuilder(
                  'wallet-journal-type-$value',
                  walletJournalFilterLabel(value, i18n),
                  value == (selection.journalType ?? 'all'),
                  () => onChanged(selection.copyWith(
                      journalType: value, clearJournalType: value == 'all'))),
          ]),
      const SizedBox(height: AppTokens.s7),
      _section(
          context,
          i18n.t(
              zhHans: '资金变动',
              zhHant: '資金變動',
              en: 'Asset change',
              ja: '資産変動',
              ko: '자산 변동'),
          [
            for (final value in [
              'all',
              'income',
              'expense',
              'freeze',
              'unfreeze',
              'neutral'
            ])
              optionBuilder(
                  'wallet-journal-direction-$value',
                  walletJournalFilterLabel(value, i18n),
                  value ==
                      (selection.journalDirection ??
                          switch (selection.direction) {
                            WalletRecordDirection.all => 'all',
                            WalletRecordDirection.income => 'income',
                            WalletRecordDirection.expenditure => 'expense',
                          }),
                  () => onChanged(selection.copyWith(
                      direction: WalletRecordDirection.all,
                      journalDirection: value,
                      clearJournalDirection: value == 'all'))),
          ]),
    ]);
  }

  Widget _section(BuildContext context, String title, List<Widget> options) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                color: WalletPageColors.of(context).text,
                fontSize: WalletRecordTokens.amount,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: AppTokens.s4),
        Wrap(
            spacing: AppTokens.s3, runSpacing: AppTokens.s3, children: options),
      ]);
}
