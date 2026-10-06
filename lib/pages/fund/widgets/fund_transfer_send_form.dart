// Adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../services/fund_models.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'fund_page_colors.dart';
import 'fund_send_tokens.dart';
import 'fund_recipient_user_id.dart';
import 'fund_coin_icon.dart';

/// Reference transfer presentation; the page owns form and payment state.
class FundTransferSendForm extends StatelessWidget {
  const FundTransferSendForm({
    super.key,
    required this.isGroup,
    required this.isLocked,
    required this.isLoading,
    required this.isSubmitting,
    required this.hasPending,
    required this.currency,
    required this.balance,
    required this.recipientID,
    required this.recipientName,
    required this.recipientFaceURL,
    required this.formKey,
    required this.amountInput,
    required this.notice,
    required this.statusBanner,
    required this.submitButton,
    required this.onClose,
    required this.onChooseCurrency,
    required this.onChooseRecipient,
  });
  final bool isGroup, isLocked, isLoading, isSubmitting, hasPending;
  final FundCurrency currency;
  final FundBalance? balance;
  final String? recipientID, recipientName, recipientFaceURL;
  final GlobalKey<FormState> formKey;
  final Widget amountInput, notice, statusBanner, submitButton;
  final VoidCallback onClose, onChooseCurrency, onChooseRecipient;
  String _text(BuildContext context, String zh, String en) =>
      settingsText(context, zh: zh, en: en);
  TextStyle _walletStyle(BuildContext context, double size,
          {Color? color, FontWeight? weight}) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: size,
          height: 1.2,
          color: color ?? FundPageColors.of(context).text,
          fontWeight: weight ?? FontWeight.w500);
  Widget _transferRecipient(BuildContext context, double scale) {
    final cs = FundPageColors.of(context);
    return InkWell(
        key: const ValueKey('fund-transfer-recipient'),
        onTap: isGroup && !isLocked && !isLoading ? onChooseRecipient : null,
        child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: FundWalletTokens.transferMargin * scale),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        recipientName == null
                            ? _text(context, '请选择收款人', 'Select a recipient')
                            : _text(context, '转账给 $recipientName',
                                'Transfer to $recipientName'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _walletStyle(context, 16 * scale,
                            weight: FontWeight.w700)),
                    SizedBox(height: 4 * scale),
                    FundRecipientUserID(
                        userID: recipientID,
                        style: _walletStyle(context, 14 * scale,
                            color: cs.subText, weight: FontWeight.w400)),
                  ])),
              SizedBox(width: 12 * scale),
              AvatarView(
                  width: FundWalletTokens.transferAvatar * scale,
                  height: FundWalletTokens.transferAvatar * scale,
                  url: recipientFaceURL,
                  text: recipientName,
                  textStyle: _walletStyle(context, 16 * scale,
                      color: AppTokens.onAccent, weight: FontWeight.w600),
                  isCircle: true),
              if (isGroup) ...[
                SizedBox(width: 6 * scale),
                Icon(Icons.chevron_right_rounded,
                    size: 22 * scale, color: cs.subText)
              ],
            ])));
  }

  Widget _coinPill(BuildContext context, double scale) {
    final cs = FundPageColors.of(context);
    return InkWell(
        key: const ValueKey('fund-currency'),
        onTap: isLocked || isLoading ? null : onChooseCurrency,
        borderRadius: BorderRadius.circular(12 * scale),
        child: Container(
            height: 40 * scale,
            padding: EdgeInsets.symmetric(horizontal: 12 * scale),
            decoration: BoxDecoration(
                color: cs.inputFill,
                borderRadius: BorderRadius.circular(12 * scale),
                border: Border.all(color: cs.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 72 * scale),
                  child: Text(balance?.available.displayDecimal ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _walletStyle(context, 13.5 * scale))),
              SizedBox(width: 6 * scale),
              FundCoinIcon(currency: currency, size: 24 * scale),
              SizedBox(width: 6 * scale),
              Text(currency.displayName,
                  style: _walletStyle(context, 13.5 * scale,
                      weight: FontWeight.w700)),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    final scale = (MediaQuery.sizeOf(context).width / 375).clamp(.92, 1.0);
    return SafeArea(
        bottom: false,
        child: Form(
            key: formKey,
            child: Column(children: [
              SizedBox(
                  height: FundWalletTokens.transferBar * scale,
                  child: Row(children: [
                    SizedBox(width: 4 * scale),
                    IconButton(
                        key: const ValueKey('fund-close'),
                        tooltip:
                            MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: isSubmitting ? null : onClose,
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            color: cs.blue, size: 19 * scale)),
                  ])),
              Expanded(
                  child: Stack(children: [
                ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                        top: FundWalletTokens.transferTop * scale,
                        bottom: 120 * scale),
                    children: [
                      if (isLoading)
                        const Center(child: CircularProgressIndicator()),
                      _transferRecipient(context, scale),
                      SizedBox(height: FundWalletTokens.transferGap * scale),
                      Container(
                          key: const ValueKey('fund-transfer-amount-card'),
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                              24 * scale, 18 * scale, 24 * scale, 12 * scale),
                          decoration: BoxDecoration(
                              color: cs.card,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(
                                      FundWalletTokens.transferRadius * scale)),
                              boxShadow: [
                                BoxShadow(
                                    color: cs.shadow,
                                    blurRadius: 12,
                                    offset: const Offset(0, -2))
                              ]),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (MediaQuery.textScalerOf(context).scale(1) >
                                    1.5)
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            _text(context, '转账金额',
                                                'Transfer Amount'),
                                            style: _walletStyle(
                                                context, 14.5 * scale,
                                                weight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        _coinPill(context, scale),
                                      ])
                                else
                                  Row(children: [
                                    Text(
                                        _text(
                                            context, '转账金额', 'Transfer Amount'),
                                        style: _walletStyle(
                                            context, 14.5 * scale,
                                            weight: FontWeight.w700)),
                                    const Spacer(),
                                    _coinPill(context, scale),
                                  ]),
                                SizedBox(height: 18 * scale),
                                amountInput,
                                Container(
                                    height: 1,
                                    margin: EdgeInsets.only(top: 8 * scale),
                                    color: cs.line),
                                SizedBox(height: 14 * scale),
                                ConstrainedBox(
                                    constraints:
                                        BoxConstraints(minHeight: 44 * scale),
                                    child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: notice)),
                              ])),
                    ]),
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: FundWalletTokens.transferButtonBottom * scale,
                    child: Center(child: submitButton)),
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: (FundWalletTokens.transferButtonBottom +
                            FundWalletTokens.transferButtonHeight +
                            12) *
                        scale,
                    child: statusBanner),
              ])),
            ])));
  }
}
