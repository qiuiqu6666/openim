import 'package:openim_common/localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../services/fund_models.dart';
import '../../../fund/widgets/fund_coin_icon.dart';
import '../../../fund/widgets/fund_send_tokens.dart';
import '../models/live_tip_currency.dart';
import '../widgets/live_style.dart';

/// Presentation only; the owning sheet keeps payment and pending-order state.
class LiveTipForm extends StatelessWidget {
  const LiveTipForm({
    super.key,
    required this.currencies,
    required this.currency,
    required this.amount,
    required this.memo,
    required this.loading,
    required this.busy,
    required this.pending,
    required this.pendingUnavailable,
    required this.balance,
    required this.balanceLoading,
    required this.balanceFailed,
    required this.onRefreshBalance,
    required this.onCurrency,
    required this.onAmountChanged,
    required this.onClose,
    required this.onSubmit,
    this.error,
  });

  final List<LiveTipCurrency> currencies;
  final LiveTipCurrency? currency;
  final TextEditingController amount, memo;
  final bool loading, busy, pending, pendingUnavailable;
  final FundBalance? balance;
  final bool balanceLoading, balanceFailed;
  final VoidCallback onRefreshBalance, onClose, onAmountChanged;
  final ValueChanged<String> onCurrency;
  final VoidCallback? onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = LiveStyle.secondary(context);
    final editable = !busy && !pending;
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(LiveStyle.fieldRadius),
        borderSide: BorderSide.none);
    InputDecoration decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: secondary),
        filled: true,
        fillColor: LiveStyle.field(context),
        contentPadding: const EdgeInsets.all(AppTokens.s5),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: AppTokens.accent)));

    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
            top: false,
            child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s5),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                          child: Container(
                              width: LiveStyle.guideHandleWidth,
                              height: LiveStyle.guideHandleHeight,
                              decoration: BoxDecoration(
                                  color: LiveStyle.guideHandle(context),
                                  borderRadius: BorderRadius.circular(
                                      LiveStyle.fieldRadius)))),
                      Row(children: [
                        Expanded(
                            child: Text(AppCopy.text('打赏主播'),
                                style: text.titleLarge?.copyWith(
                                    color: LiveStyle.text(context),
                                    fontWeight: FontWeight.w600))),
                        IconButton(
                            tooltip: AppCopy.text('关闭'),
                            onPressed: busy ? null : onClose,
                            color: secondary,
                            icon: const Icon(CupertinoIcons.xmark_circle_fill))
                      ]),
                      const SizedBox(height: AppTokens.s4),
                      if (loading)
                        const Center(child: CircularProgressIndicator())
                      else if (pendingUnavailable)
                        Text(AppCopy.text('上次打赏使用的币种已不再提供，请到钱包核对原交易。'))
                      else if (currencies.isEmpty)
                        Text(AppCopy.text('暂无可用打赏币种，请稍后重试。'))
                      else ...[
                        // A single supported currency needs no segmented control.
                        if (currencies.length == 1)
                          _currencyLabel(context, currencies.single, true)
                        else
                          CupertinoSlidingSegmentedControl<String>(
                              groupValue: currency?.code,
                              disabledChildren: editable
                                  ? const <String>{}
                                  : currencies
                                      .map((value) => value.code)
                                      .toSet(),
                              backgroundColor: LiveStyle.field(context),
                              thumbColor: LiveStyle.card(context),
                              onValueChanged: (value) {
                                if (editable && value != null) {
                                  onCurrency(value);
                                }
                              },
                              children: {
                                for (final value in [
                                  ...currencies.where((v) =>
                                      v.code == FundCurrency.bi99.code),
                                  ...currencies.where((v) =>
                                      v.code == FundCurrency.usdt.code),
                                  ...currencies.where((v) =>
                                      v.code != FundCurrency.bi99.code &&
                                      v.code != FundCurrency.usdt.code),
                                ])
                                  value.code: _currencyLabel(context, value,
                                      value.code == currency?.code)
                              }),
                        const SizedBox(height: AppTokens.s6),
                        Text(AppCopy.text('打赏金额'),
                            style: text.bodyMedium?.copyWith(color: secondary)),
                        const SizedBox(height: AppTokens.s3),
                        TextField(
                            key: const ValueKey('live-tip-amount'),
                            controller: amount,
                            enabled: editable,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => onAmountChanged(),
                            style: text.headlineLarge?.copyWith(
                                fontSize: FundWalletTokens.payAmount,
                                color: LiveStyle.text(context),
                                fontWeight: FontWeight.w600),
                            decoration: decoration('0.00').copyWith(
                                suffixText: currency?.label,
                                suffixStyle: text.titleMedium
                                    ?.copyWith(color: secondary))),
                        Row(children: [
                          Expanded(
                              child: Text(
                                  balanceLoading
                                      ? AppCopy.text('可用余额加载中…')
                                      : balanceFailed || balance == null
                                          ? AppCopy.text('余额暂不可用，请重试')
                                          : AppCopy.format('可用余额 {#0} {#1}', [
                                              balance!.available.displayDecimal,
                                              currency!.label
                                            ]),
                                  key: const ValueKey('live-tip-balance'),
                                  style: text.bodySmall
                                      ?.copyWith(color: secondary))),
                          IconButton(
                              tooltip: balanceFailed
                                  ? AppCopy.text('重试余额')
                                  : AppCopy.text('刷新余额'),
                              onPressed: balanceLoading || busy
                                  ? null
                                  : onRefreshBalance,
                              icon: const Icon(CupertinoIcons.refresh,
                                  size: LiveStyle.controlIconSize),
                              color: secondary)
                        ]),
                        const SizedBox(height: AppTokens.s3),
                        TextField(
                            key: const ValueKey('live-tip-memo'),
                            controller: memo,
                            enabled: editable,
                            maxLength: 50,
                            minLines: 1,
                            maxLines: 2,
                            textInputAction: TextInputAction.done,
                            style: text.bodyLarge
                                ?.copyWith(color: LiveStyle.text(context)),
                            decoration: decoration(AppCopy.text('备注（选填）'))),
                        if (pending)
                          Text(AppCopy.text('上次打赏结果待确认，重试将使用同一订单号。'),
                              style:
                                  text.bodySmall?.copyWith(color: secondary)),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: AppTokens.s3),
                        Text(error!,
                            style:
                                text.bodyMedium?.copyWith(color: LiveStyle.red))
                      ],
                      const SizedBox(height: AppTokens.s5),
                      LivePrimaryButton(
                          label: pending
                              ? AppCopy.text('重试原交易')
                              : AppCopy.text('确认打赏'),
                          busy: busy,
                          onPressed:
                              loading || pendingUnavailable ? null : onSubmit)
                    ]))));
  }

  Widget _currencyLabel(
      BuildContext context, LiveTipCurrency value, bool selected) {
    return Padding(
        key: ValueKey('live-tip-currency-${value.code}'),
        padding: const EdgeInsets.symmetric(
            vertical: AppTokens.s4, horizontal: AppTokens.s3),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FundCoinIcon(
              currency: FundCurrency.parse(value.code),
              size: LiveStyle.controlIconSize),
          const SizedBox(width: AppTokens.s3),
          Flexible(
              child: Text(value.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected
                          ? AppTokens.accent
                          : LiveStyle.secondary(context),
                      fontWeight: FontWeight.w600)))
        ]));
  }
}
