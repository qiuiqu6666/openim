import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../widgets/wallet_coin_logo.dart';
import '../../wallet_repository.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_exchange_tokens.dart';

class WalletExchangeForm extends StatelessWidget {
  const WalletExchangeForm(
      {super.key,
      required this.from,
      required this.to,
      required this.amountController,
      required this.available,
      required this.locked,
      required this.onFrom,
      required this.onTo,
      required this.onReverse,
      required this.onAmountChanged,
      this.outputAmount = '--',
      this.outputEstimated = false});

  final FundCurrency from, to;
  final TextEditingController amountController;
  final String available;
  final bool locked;
  final String outputAmount;
  final bool outputEstimated;
  final ValueChanged<FundCurrency> onFrom, onTo;
  final VoidCallback onReverse, onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return Container(
      decoration: BoxDecoration(
          color: WalletExchangeTokens.panel(context),
          borderRadius: BorderRadius.circular(AppTokens.rXl)),
      child: Column(children: [
        _currency(context, from, 'wallet-swap-from', '转出',
            '$available ${from.displayName}', onFrom,
            available: true),
        SizedBox(
          height: AppTokens.buttonHeight,
          child: Stack(alignment: Alignment.center, children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                child: Divider(height: 1, color: colors.line)),
            IconButton(
                key: const ValueKey('wallet-swap-reverse'),
                tooltip: '交换币种',
                onPressed: locked ? null : onReverse,
                style: IconButton.styleFrom(
                    backgroundColor: colors.card,
                    side: BorderSide(color: colors.line),
                    minimumSize: const Size.square(AppTokens.buttonHeight)),
                color: colors.text,
                disabledColor: colors.subText,
                icon: const Icon(Icons.swap_vert_rounded)),
          ]),
        ),
        _currency(context, to, 'wallet-swap-to', '转入',
            '$outputAmount ${to.displayName}', onTo),
      ]),
    );
  }

  Widget _currency(BuildContext context, FundCurrency currency, String key,
      String label, String quantity, ValueChanged<FundCurrency> changed,
      {bool available = false}) {
    final colors = WalletPageColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5, vertical: AppTokens.s3),
      child: DropdownButtonHideUnderline(
          child: DropdownButton<FundCurrency>(
        key: ValueKey(key),
        value: currency,
        isExpanded: true,
        itemHeight: null,
        dropdownColor: colors.card,
        icon: const SizedBox.shrink(),
        selectedItemBuilder: (_) => FundCurrency.values
            .map((coin) => _selectedRow(context, coin, label, quantity,
                available: available))
            .toList(),
        items: FundCurrency.values
            .map((coin) =>
                DropdownMenuItem(value: coin, child: Text(coin.displayName)))
            .toList(),
        onChanged: locked
            ? null
            : (value) {
                if (value != null) changed(value);
              },
      )),
    );
  }

  Widget _selectedRow(
      BuildContext context, FundCurrency coin, String label, String quantity,
      {required bool available}) {
    final colors = WalletPageColors.of(context);
    final theme = Theme.of(context);
    final body = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: WalletExchangeTokens.bodyFont, color: colors.text);
    final caption = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: WalletExchangeTokens.captionFont, color: colors.subText);
    final labels = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: caption),
          Text(coin.displayName,
              style: body.copyWith(fontWeight: FontWeight.w600)),
        ]);
    final quantities = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(quantity,
              key: coin == (available ? from : to)
                  ? ValueKey(available
                      ? 'wallet-swap-available'
                      : 'wallet-swap-output')
                  : null,
              textAlign: TextAlign.end,
              style: body),
          Text(
              available
                  ? '可用余额'
                  : outputAmount == '--'
                      ? '成交后显示'
                      : outputEstimated
                          ? '预计实得'
                          : '实得数量',
              style: caption),
        ]);
    final logo = WalletCoinLogo(
        size: WalletExchangeTokens.coinSize,
        type: coin == FundCurrency.bi99
            ? CoinType.cny
            : coin == FundCurrency.trx
                ? CoinType.trx
                : CoinType.usdt);
    final arrow = ExcludeSemantics(
        child: Icon(Icons.chevron_right_rounded,
            size: AppTokens.s7, color: locked ? colors.subText : colors.text));
    return LayoutBuilder(builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.25;
      if (largeText ||
          constraints.maxWidth < WalletExchangeTokens.stackedCurrencyWidth) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            logo,
            const SizedBox(width: AppTokens.s4),
            Expanded(child: labels),
            arrow
          ]),
          const SizedBox(height: AppTokens.s3),
          Align(alignment: Alignment.centerRight, child: quantities),
        ]);
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: WalletExchangeTokens.rowHeight - AppTokens.s5),
        child: Row(children: [
          logo,
          const SizedBox(width: AppTokens.s4),
          Expanded(child: labels),
          const SizedBox(width: AppTokens.s3),
          Expanded(flex: 2, child: quantities),
          const SizedBox(width: AppTokens.s3),
          arrow
        ]),
      );
    });
  }
}
