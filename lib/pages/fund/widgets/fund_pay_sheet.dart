// Adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_api.dart';
import '../../../widgets/payment/password_payment_sheet.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'fund_page_colors.dart';
import 'fund_send_tokens.dart';
import 'fund_coin_icon.dart';

class FundPaymentDetails {
  const FundPaymentDetails({required this.total, required this.available});
  final FundAmount total;
  final String available;
}

/// Fund presentation only. The shared sheet owns the payment state machine;
/// its callback remains responsible for the fund API and original order ID.
class FundPaySheet extends StatelessWidget {
  const FundPaySheet({
    super.key,
    required this.total,
    required this.recipient,
    required this.title,
    required this.available,
    required this.onPay,
    this.onSuccess,
    this.errorMessage,
    this.onError,
    this.paymentDetails,
    this.onChangePaymentMethod,
    this.canChangePaymentMethod,
  });
  final FundAmount total;
  final String recipient, title, available;
  final Future<FundOrder> Function(String password) onPay;
  final FutureOr<void> Function(FundOrder result)? onSuccess;
  final String Function(Object error)? errorMessage;
  final ValueChanged<String>? onError;
  final FundPaymentDetails Function()? paymentDetails;
  final Future<bool> Function()? onChangePaymentMethod;
  final bool Function()? canChangePaymentMethod;

  @override
  Widget build(BuildContext context) => PasswordPaymentSheet<FundOrder>(
        title: title,
        summaryBuilder: (context, changePaymentMethod) {
          final details = paymentDetails?.call() ??
              FundPaymentDetails(total: total, available: available);
          return _FundPaymentSummary(
              total: details.total,
              recipient: recipient,
              available: details.available,
              onChangePaymentMethod: changePaymentMethod);
        },
        onChangePaymentMethod: onChangePaymentMethod,
        canChangePaymentMethod: canChangePaymentMethod,
        onPay: onPay,
        onSuccess: onSuccess,
        onError: onError,
        errorMessage: errorMessage ??
            (error) => error is PasswordPaymentException
                ? error.message
                : fundErrorMessage(error,
                    chinese:
                        Localizations.localeOf(context).languageCode != 'en'),
        keys: const PaymentSheetKeys(
          sheet: ValueKey('fund-payment-sheet'),
          password: ValueKey('fund-pay-password'),
          confirm: ValueKey('fund-confirm-pay'),
          cancel: ValueKey('fund-cancel-pay'),
          keypad: ValueKey('fund-payment-keypad'),
        ),
      );
}

class _FundPaymentSummary extends StatelessWidget {
  const _FundPaymentSummary(
      {required this.total,
      required this.recipient,
      required this.available,
      this.onChangePaymentMethod});
  final FundAmount total;
  final String recipient, available;
  final VoidCallback? onChangePaymentMethod;

  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    TextStyle style(double size, Color color, FontWeight weight) =>
        Theme.of(context)
            .textTheme
            .bodyMedium!
            .copyWith(fontSize: size, color: color, fontWeight: weight);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 2),
      Semantics(
          label:
              '$recipient, ${total.displayDecimal} ${total.currency.displayName}',
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(total.displayDecimal,
                        style: style(FundWalletTokens.payAmount, cs.text,
                                FontWeight.w600)
                            .copyWith(height: 1)),
                    Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(total.currency.displayName,
                            style: style(FundWalletTokens.payCoin, cs.subText,
                                    FontWeight.w500)
                                .copyWith(height: 1))),
                  ]))),
      const SizedBox(height: 14),
      Text(settingsText(context, zh: '付款方式', en: 'Payment Method'),
          style: style(12, cs.subText, FontWeight.w400)),
      const SizedBox(height: 6),
      Semantics(
        button: onChangePaymentMethod != null,
        enabled: onChangePaymentMethod != null,
        label:
            settingsText(context, zh: '更换支付币种', en: 'Change payment currency'),
        child: Material(
            color: FundTokens.transparent,
            child: InkWell(
                key: const ValueKey('fund-pay-change-currency'),
                onTap: onChangePaymentMethod,
                borderRadius:
                    BorderRadius.circular(FundWalletTokens.payCardRadius),
                child: Container(
                    key: const ValueKey('fund-pay-wallet-card'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                        color: cs.blue.withValues(alpha: cs.dark ? .18 : .08),
                        borderRadius: BorderRadius.circular(
                            FundWalletTokens.payCardRadius)),
                    child: Row(children: [
                      FundCoinIcon(
                          currency: total.currency,
                          size: FundWalletTokens.payMethodLogo),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                settingsText(context,
                                    zh: '我的钱包', en: 'My Wallet'),
                                style: style(13.5, cs.text, FontWeight.w500)),
                            const SizedBox(height: 5),
                            Text('$available ${total.currency.displayName}',
                                style: style(11, cs.subText, FontWeight.w400)),
                          ])),
                      if (onChangePaymentMethod != null) ...[
                        Text(settingsText(context, zh: '更换', en: 'Change'),
                            style: style(11, cs.subText, FontWeight.w400)),
                        Icon(Icons.chevron_right_rounded,
                            size: 21, color: cs.subText),
                      ] else
                        Icon(Icons.check_rounded, size: 21, color: cs.blue),
                    ])))),
      ),
      const SizedBox(height: 11),
    ]);
  }
}
