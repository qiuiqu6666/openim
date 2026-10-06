// Adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
// Source: lib/src/pages/wallet/widgets/pay_method_sheet.dart.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_models.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'fund_page_colors.dart';
import 'fund_coin_icon.dart';

class FundPayMethodSheet extends StatefulWidget {
  const FundPayMethodSheet(
      {super.key, required this.balances, required this.selected});
  final List<FundBalance> balances;
  final FundCurrency selected;
  @override
  State<FundPayMethodSheet> createState() => _FundPayMethodSheetState();
}

class _FundPayMethodSheetState extends State<FundPayMethodSheet> {
  late FundCurrency _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final upper = viewport.height * .94;
    final maxHeight =
        (viewport.height * (.86 + math.max(0.0, textScale - 1) * .06))
            .clamp(math.min(420.0, upper), upper)
            .toDouble();
    TextStyle style(double size, Color color, FontWeight weight,
            {double? height}) =>
        Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: size, color: color, fontWeight: weight, height: height);

    return Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: EdgeInsets.fromLTRB(
            18, 8, 18, 10 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
            color: cs.card,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: cs.line.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(49.5))),
          const SizedBox(height: 4),
          Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                  button: true,
                  label: MaterialLocalizations.of(context).closeButtonTooltip,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                          key: const ValueKey('fund-pay-method-close'),
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: cs.inputFill, shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              color: cs.subText, size: 14))))),
          const SizedBox(height: 2),
          Align(
              alignment: Alignment.centerLeft,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        settingsText(context,
                            zh: '选择付款方式', en: 'Select Payment Method'),
                        style:
                            style(18, cs.text, FontWeight.w800, height: 1.15)),
                    const SizedBox(height: 5),
                    Text(
                        settingsText(context,
                            zh: '选择用于本次支付的币种',
                            en: 'Choose currency for this payment'),
                        style: style(12, cs.subText, FontWeight.w400,
                            height: 1.2)),
                  ])),
          const SizedBox(height: 14),
          Flexible(
              child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: widget.balances.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final balance = widget.balances[index];
                    return _PayMethodRow(
                        balance: balance,
                        selected: balance.currency == _selected,
                        cs: cs,
                        onTap: () =>
                            setState(() => _selected = balance.currency));
                  })),
          const SizedBox(height: 11),
          Semantics(
              button: true,
              child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(_selected),
                  child: Container(
                      key: const ValueKey('fund-pay-method-confirm'),
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: cs.blue,
                          borderRadius: BorderRadius.circular(49.5),
                          boxShadow: [
                            BoxShadow(
                                color: cs.blue.withValues(alpha: .28),
                                blurRadius: 18,
                                offset: const Offset(0, 8))
                          ]),
                      child: Text(
                          settingsText(context,
                              zh: '确认支付', en: 'Confirm Payment'),
                          style: style(
                              15, AppTokens.onAccent, FontWeight.w700))))),
        ]));
  }
}

class _PayMethodRow extends StatelessWidget {
  const _PayMethodRow(
      {required this.balance,
      required this.selected,
      required this.cs,
      required this.onTap});
  final FundBalance balance;
  final bool selected;
  final FundPageColors cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedBg = cs.blue.withValues(alpha: cs.dark ? .16 : .06);
    TextStyle style(double size, Color color, FontWeight weight,
            {double? height}) =>
        Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: size, color: color, fontWeight: weight, height: height);
    return Material(
        color: FundTokens.transparent,
        child: InkWell(
            key: ValueKey('fund-pay-method-${balance.currency.code}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Container(
                constraints: const BoxConstraints(minHeight: 66),
                padding: const EdgeInsets.fromLTRB(12, 8, 11, 8),
                decoration: BoxDecoration(
                    color: selected ? selectedBg : cs.card,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: selected ? cs.blue : cs.line,
                        width: selected ? 1 : .75)),
                child: Row(children: [
                  FundCoinIcon(currency: balance.currency, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(balance.currency.displayName,
                            style:
                                style(15, cs.text, FontWeight.w800, height: 1)),
                        const SizedBox(height: 6),
                        // The backend has no chain/fiat fields. Platform coin
                        // is factual; other tags use the actual currency code.
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: selected
                                    ? cs.blue
                                        .withValues(alpha: cs.dark ? .28 : .12)
                                    : cs.inputFill,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(
                                balance.currency == FundCurrency.bi99
                                    ? settingsText(context,
                                        zh: '平台币', en: 'Platform')
                                    : balance.currency.displayName,
                                style: style(
                                    10,
                                    selected
                                        ? cs.blue
                                        : cs.subText.withValues(alpha: .85),
                                    FontWeight.w600,
                                    height: 1.1))),
                      ])),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        Container(
                            key: ValueKey(
                                'fund-pay-method-mark-${balance.currency.code}'),
                            width: 17,
                            height: 17,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: selected ? cs.blue : null,
                                shape: BoxShape.circle,
                                border: selected
                                    ? null
                                    : Border.all(
                                        color:
                                            cs.subText.withValues(alpha: .35))),
                            child: selected
                                ? const Icon(Icons.check_rounded,
                                    size: 10, color: AppTokens.onAccent)
                                : null),
                        const SizedBox(height: 4),
                        FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(balance.available.displayDecimal,
                                textAlign: TextAlign.end,
                                style: style(15, cs.text, FontWeight.w700,
                                    height: 1))),
                      ])),
                ]))));
  }
}
