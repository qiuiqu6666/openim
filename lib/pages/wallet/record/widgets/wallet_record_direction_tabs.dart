import 'package:flutter/material.dart';

import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../filters/wallet_record_filters.dart';
import '../wallet_record_tokens.dart';

class WalletRecordDirectionTabs extends StatelessWidget {
  const WalletRecordDirectionTabs(
      {super.key, required this.selected, required this.onChanged});
  final WalletRecordDirection selected;
  final ValueChanged<WalletRecordDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final labels = {
      WalletRecordDirection.all:
          i18n.t(zhHans: '全部', zhHant: '全部', en: 'All', ja: 'すべて', ko: '전체'),
      WalletRecordDirection.expenditure: i18n.t(
          zhHans: '支出', zhHant: '支出', en: 'Expenses', ja: '支出', ko: '지출'),
      WalletRecordDirection.income:
          i18n.t(zhHans: '收入', zhHant: '收入', en: 'Income', ja: '収入', ko: '수입'),
    };
    return Material(
      color: colors.card,
      child: Column(children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final direction in WalletRecordDirection.values)
              Expanded(
                child: Semantics(
                  key: ValueKey('wallet-record-tab-${direction.name}'),
                  container: true,
                  button: true,
                  label: labels[direction],
                  selected: direction == selected,
                  onTap: () => onChanged(direction),
                  child: ExcludeSemantics(
                      child: TextButton(
                    onPressed: () => onChanged(direction),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.square(WalletRecordTokens.minTap),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.s2, vertical: AppTokens.s3),
                      foregroundColor: direction == selected
                          ? WalletRecordTokens.selectedTab(context)
                          : colors.text,
                      shape: const RoundedRectangleBorder(),
                      textStyle: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(
                              fontSize: WalletRecordTokens.amount,
                              fontWeight: direction == selected
                                  ? FontWeight.w600
                                  : FontWeight.w400),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(labels[direction]!, textAlign: TextAlign.center),
                      const SizedBox(height: AppTokens.s3),
                      SizedBox(
                          width: WalletRecordTokens.tabIndicator,
                          height: WalletRecordTokens.indicatorHeight,
                          child: ColoredBox(
                              color: direction == selected
                                  ? colors.blue
                                  : Colors.transparent)),
                    ]),
                  )),
                ),
              ),
          ]),
        ),
        Divider(
            height: WalletRecordTokens.divider,
            thickness: WalletRecordTokens.divider,
            color: colors.line),
      ]),
    );
  }
}
