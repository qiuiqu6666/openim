import 'package:flutter/material.dart';

import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../filters/wallet_record_filters.dart';
import '../wallet_record_models.dart';
import '../wallet_record_tokens.dart';
import 'wallet_record_row.dart';

class WalletRecordMonthSection extends StatelessWidget {
  const WalletRecordMonthSection(
      {super.key,
      required this.group,
      required this.months,
      required this.onMonthChanged,
      required this.onOpenRecord,
      this.headerOnly = false});
  final WalletRecordMonthGroup group;
  final List<WalletRecordMonthGroup> months;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<WalletRecordDto> onOpenRecord;
  final bool headerOnly;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final month = group.month;
    final year = month == null || month.year == DateTime.now().year
        ? ''
        : '${month.year} · ';
    return Padding(
      key: ValueKey('wallet-record-month-${group.key}'),
      padding: const EdgeInsets.only(bottom: AppTokens.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<String>(
            key: ValueKey('wallet-record-month-picker-${group.key}'),
            tooltip: i18n.t(
                zhHans: '选择月份',
                zhHant: '選擇月份',
                en: 'Select month',
                ja: '月を選択',
                ko: '월 선택'),
            onSelected: onMonthChanged,
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'all',
                  child: Text(i18n.t(
                      zhHans: '全部月份',
                      zhHant: '全部月份',
                      en: 'All months',
                      ja: 'すべての月',
                      ko: '모든 월'))),
              for (final option in months.where((g) => g.month != null))
                PopupMenuItem(
                    value: option.key,
                    child: Text(
                        '${option.month!.year}-${option.month!.month.toString().padLeft(2, '0')}')),
            ],
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: WalletRecordTokens.minTap),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s4, vertical: AppTokens.s4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: month == null
                          ? Text(
                              i18n.t(
                                  zhHans: '时间未知',
                                  zhHant: '時間未知',
                                  en: 'Unknown date',
                                  ja: '日時不明',
                                  ko: '날짜 알 수 없음'),
                              style: TextStyle(
                                  color: colors.text,
                                  fontSize: WalletRecordTokens.body))
                          : Text.rich(
                              TextSpan(
                                  text: year,
                                  style: const TextStyle(
                                      fontSize: WalletRecordTokens.body),
                                  children: [
                                    TextSpan(
                                        text: '${month.month}',
                                        style: const TextStyle(
                                            fontSize: WalletRecordTokens.month,
                                            fontWeight: FontWeight.w700)),
                                    TextSpan(
                                        text: i18n.t(
                                            zhHans: '月',
                                            zhHant: '月',
                                            en: ' month',
                                            ja: '月',
                                            ko: '월'),
                                        style: const TextStyle(
                                            fontSize: WalletRecordTokens.body)),
                                  ]),
                              style: TextStyle(color: colors.text))),
                  Icon(Icons.arrow_drop_down_rounded,
                      color: colors.text, size: AppTokens.s7),
                ]),
              ),
            ),
          ),
        ),
        if (!headerOnly)
          Material(
            key: ValueKey('wallet-record-group-${group.key}'),
            color: colors.card,
            borderRadius: BorderRadius.circular(AppTokens.rCard),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var index = 0; index < group.records.length; index++) ...[
                if (index != 0)
                  Divider(
                      height: WalletRecordTokens.divider,
                      thickness: WalletRecordTokens.divider,
                      color: colors.line,
                      indent: AppTokens.s4 +
                          WalletRecordTokens.avatar +
                          AppTokens.s4),
                WalletRecordRow(
                    item: group.records[index],
                    onTap: () => onOpenRecord(group.records[index])),
              ],
            ]),
          ),
      ]),
    );
  }
}
