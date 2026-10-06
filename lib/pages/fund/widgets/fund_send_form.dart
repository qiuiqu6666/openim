// Adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import '../../../services/fund_models.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'fund_page_colors.dart';
import 'fund_send_tokens.dart';
import 'fund_coin_icon.dart';
import 'fund_transfer_send_form.dart';

/// The reference wallet layout. All payment state and resources belong to
/// FundSendPage; this component only renders values and invokes callbacks.
class FundSendForm extends StatelessWidget {
  const FundSendForm({
    super.key,
    required this.isRedPacket,
    required this.isGroup,
    required this.isMultiple,
    required this.isLocked,
    required this.isLoading,
    required this.isSubmitting,
    required this.passwordSet,
    required this.hasBalances,
    required this.hasPending,
    required this.currency,
    required this.biz,
    required this.amount,
    required this.count,
    required this.remark,
    required this.amountFocus,
    required this.formKey,
    required this.total,
    required this.balance,
    required this.recipientID,
    required this.recipientName,
    required this.recipientFaceURL,
    required this.error,
    required this.onEdited,
    required this.onChooseType,
    required this.onChooseCurrency,
    required this.onChooseRecipient,
    required this.onSubmit,
    required this.onReload,
    required this.onSetPassword,
    required this.onClose,
    required this.validateAmount,
    required this.validateRemark,
  });
  final bool isRedPacket,
      isGroup,
      isMultiple,
      isLocked,
      isLoading,
      isSubmitting,
      passwordSet,
      hasPending,
      hasBalances;
  final FundCurrency currency;
  final FundPacketBiz biz;
  final TextEditingController amount, count, remark;
  final FocusNode amountFocus;
  final GlobalKey<FormState> formKey;
  final FundAmount? total;
  final FundBalance? balance;
  final String? recipientID, recipientName, recipientFaceURL, error;
  final VoidCallback onEdited,
      onChooseType,
      onChooseCurrency,
      onChooseRecipient,
      onSubmit,
      onReload,
      onSetPassword,
      onClose;
  final FormFieldValidator<String> validateAmount, validateRemark;
  String _text(BuildContext context, String zh, String en) =>
      settingsText(context, zh: zh, en: en);
  TextStyle _walletStyle(BuildContext context, double size,
          {Color? color, FontWeight? weight}) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: size,
          height: 1.2,
          color: color ?? FundPageColors.of(context).text,
          fontWeight: weight ?? FontWeight.w500);
  String _bizLabel(BuildContext context, FundPacketBiz biz) => switch (biz) {
        FundPacketBiz.normal => _text(context, '普通红包', 'Regular packet'),
        FundPacketBiz.lucky => _text(context, '拼手气红包', 'Lucky packet'),
        FundPacketBiz.exclusive => _text(context, '专属红包', 'Exclusive packet'),
      };
  Widget _amountField(BuildContext context, {bool transfer = false}) {
    final cs = FundPageColors.of(context);
    final scale = (MediaQuery.sizeOf(context).width / 375).clamp(.92, 1.0);
    final size = transfer
        ? FundWalletTokens.transferInputFont * scale
        : FundWalletTokens.fieldInputFont;
    return Semantics(
        label: isMultiple && biz == FundPacketBiz.normal
            ? _text(context, '单个金额', 'Amount per packet')
            : _text(context, '金额', 'Amount'),
        child: TextFormField(
            key: const ValueKey('fund-amount'),
            controller: amount,
            focusNode: amountFocus,
            enabled: !isLocked && !isLoading,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: transfer ? TextAlign.left : TextAlign.right,
            textAlignVertical: TextAlignVertical.center,
            cursorColor: cs.inputCursor,
            style: _walletStyle(context, size),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: '0',
                hintStyle: _walletStyle(context, size,
                    color: cs.inputHint, weight: FontWeight.w400),
                errorMaxLines: 3),
            validator: validateAmount,
            onChanged: (_) => onEdited()));
  }

  Widget _countField(
    BuildContext context,
  ) {
    final cs = FundPageColors.of(context);
    return Semantics(
        label: _text(context, '红包个数', 'Packet count'),
        child: TextFormField(
            key: const ValueKey('fund-count'),
            controller: count,
            enabled: !isLocked && !isLoading,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            textAlignVertical: TextAlignVertical.center,
            cursorColor: cs.inputCursor,
            style: _walletStyle(context, FundWalletTokens.fieldInputFont),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: _text(context, '填写红包个数', 'Number of packets'),
                hintStyle: _walletStyle(
                    context, FundWalletTokens.fieldInputFont,
                    color: cs.inputHint, weight: FontWeight.w400),
                suffixText: _text(context, '个', 'packets'),
                suffixStyle: _walletStyle(
                    context, FundWalletTokens.fieldLabelFont,
                    weight: FontWeight.w600),
                errorMaxLines: 3),
            validator: (value) {
              final count = int.tryParse(value ?? '');
              return count == null || count <= 0 || count > 2147483647
                  ? _text(context, '请输入有效的正整数',
                      'Enter a valid positive packet count')
                  : null;
            },
            onChanged: (_) => onEdited()));
  }

  Widget _inputBox(BuildContext context, Widget left, Widget right,
      {Key? key}) {
    final cs = FundPageColors.of(context);
    return Container(
        key: key,
        constraints:
            const BoxConstraints(minHeight: FundWalletTokens.fieldHeight),
        padding: const EdgeInsets.symmetric(
            horizontal: FundWalletTokens.fieldHorizontal),
        decoration: BoxDecoration(
            color: cs.card,
            borderRadius: BorderRadius.circular(FundWalletTokens.fieldRadius)),
        child: MediaQuery.textScalerOf(context).scale(1) > 1.5
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [left, right])
            : Row(children: [left, Expanded(child: right)]));
  }

  Widget _amountRow(
    BuildContext context,
  ) =>
      _inputBox(
          context,
          Text(
              isMultiple && biz == FundPacketBiz.normal
                  ? _text(context, '单个金额', 'Amount per packet')
                  : _text(context, '总金额', 'Total amount'),
              style: _walletStyle(context, FundWalletTokens.fieldLabelFont,
                  weight: FontWeight.w600)),
          _amountField(
            context,
          ),
          key: const ValueKey('fund-packet-amount-row'));
  Widget _countRow(
    BuildContext context,
  ) =>
      _inputBox(
          context,
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 14,
                height: 17,
                decoration: BoxDecoration(
                    color: FundWalletTokens.packetIconBody,
                    borderRadius: BorderRadius.circular(1.5)),
                child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(top: 2.5, right: 2.5),
                        decoration: const BoxDecoration(
                            color: FundWalletTokens.packetIconCoin,
                            shape: BoxShape.circle)))),
            const SizedBox(width: 10),
            Text(_text(context, '红包个数', 'Number of packets'),
                style: _walletStyle(context, FundWalletTokens.fieldLabelFont,
                    weight: FontWeight.w600)),
          ]),
          _countField(
            context,
          ));
  Widget _recipientRow(
    BuildContext context,
  ) {
    final cs = FundPageColors.of(context);
    return InkWell(
        onTap: isLocked || isLoading ? null : onChooseRecipient,
        borderRadius: BorderRadius.circular(FundWalletTokens.fieldRadius),
        child: _inputBox(
            context,
            Text(_text(context, '发给谁', 'Send to'),
                style: _walletStyle(context, FundWalletTokens.fieldLabelFont,
                    weight: FontWeight.w600)),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (recipientName != null) ...[
                AvatarView(
                    width: 23,
                    height: 23,
                    isCircle: true,
                    url: recipientFaceURL,
                    textStyle: _walletStyle(context, 11,
                        color: AppTokens.onAccent, weight: FontWeight.w600),
                    text: recipientName),
                const SizedBox(width: 7)
              ],
              Flexible(
                  child: Text(
                      recipientName ??
                          _text(context, '请选择接收人', 'Select recipient'),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _walletStyle(context, FundWalletTokens.typeFont,
                          color:
                              recipientName == null ? cs.inputHint : cs.text))),
              const SizedBox(width: 5),
              Icon(Icons.chevron_right_rounded,
                  size: FundWalletTokens.typeIcon, color: cs.subText),
            ])));
  }

  Widget _remarkField(BuildContext context, {bool transfer = false}) {
    final cs = FundPageColors.of(context);
    return TextFormField(
        key: const ValueKey('fund-remark'),
        controller: remark,
        enabled: !isLocked && !isLoading,
        textInputAction: TextInputAction.done,
        maxLines: 1,
        cursorColor: cs.inputCursor,
        style: _walletStyle(
            context, transfer ? 14.5 : FundWalletTokens.fieldLabelFont,
            weight: FontWeight.w500),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validateRemark,
        onChanged: (_) => onEdited(),
        decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            hintText: transfer
                ? _text(context, '添加转账说明', 'Add a note')
                : _text(context, '恭喜发财，大吉大利', 'Best wishes and good fortune.'),
            hintStyle: _walletStyle(
                context, transfer ? 14.5 : FundWalletTokens.fieldLabelFont,
                color: cs.inputHint, weight: FontWeight.w400),
            errorMaxLines: 2));
  }

  Widget _blessingInput(BuildContext context) {
    final cs = FundPageColors.of(context);
    return Container(
        key: const ValueKey('fund-default-blessing'),
        constraints:
            const BoxConstraints(minHeight: FundWalletTokens.fieldHeight),
        padding: const EdgeInsets.symmetric(
            horizontal: FundWalletTokens.fieldHorizontal),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
            color: cs.card,
            borderRadius: BorderRadius.circular(FundWalletTokens.fieldRadius)),
        child: _remarkField(context));
  }

  Widget _payCard(
    BuildContext context,
  ) {
    final cs = FundPageColors.of(context);
    return InkWell(
        key: const ValueKey('fund-currency'),
        onTap: isLocked || isLoading ? null : onChooseCurrency,
        borderRadius: BorderRadius.circular(FundWalletTokens.fieldRadius),
        child: Container(
            constraints:
                const BoxConstraints(minHeight: FundWalletTokens.payCardHeight),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
                color: cs.card,
                borderRadius:
                    BorderRadius.circular(FundWalletTokens.fieldRadius)),
            child: Row(children: [
              FundCoinIcon(
                  currency: currency, size: FundWalletTokens.payCoinSize),
              const SizedBox(width: FundWalletTokens.payCardGap),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(_text(context, '我的钱包', 'My Wallet'),
                        style: _walletStyle(
                            context, FundWalletTokens.payTitleFont)),
                    const SizedBox(height: 6),
                    Text(
                        '${balance?.available.displayDecimal ?? '—'} ${currency.displayName}',
                        style: _walletStyle(
                            context, FundWalletTokens.payBalanceFont,
                            weight: FontWeight.w800)),
                  ])),
              Text(_text(context, '更换', 'Change'),
                  style: _walletStyle(context, 12,
                      color: cs.subText, weight: FontWeight.w400)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded,
                  size: FundWalletTokens.typeIcon, color: cs.subText),
            ])));
  }

  Widget _packetTotal(BuildContext context, double font, double coinFont) =>
      Center(
          key: const ValueKey('fund-packet-total'),
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(total?.displayDecimal ?? '0.00',
                        key: const ValueKey('fund-total-amount'),
                        style: _walletStyle(context, font,
                            weight: FontWeight.w800)),
                    Text(' ${currency.displayName}',
                        style: _walletStyle(context, coinFont,
                            weight: FontWeight.w700)),
                  ])));
  Widget _sendButton(BuildContext context,
      {double? width, bool transfer = false}) {
    final cs = FundPageColors.of(context);
    final enabled = !isLoading &&
        !isSubmitting &&
        hasBalances &&
        amount.text.trim().isNotEmpty;
    final height = transfer
        ? FundWalletTokens.transferButtonHeight
        : FundWalletTokens.packetButtonHeight;
    return Semantics(
        button: true,
        enabled: enabled,
        child: Opacity(
            opacity: transfer || enabled ? 1 : .58,
            child: GestureDetector(
                onTap: enabled ? onSubmit : null,
                child: Container(
                  key: const ValueKey('fund-submit'),
                  width: width ?? double.infinity,
                  height: height +
                      (MediaQuery.textScalerOf(context).scale(1) > 1.5
                          ? 12
                          : 0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: transfer && !enabled
                          ? (cs.dark
                              ? FundWalletTokens.transferDisabledDark
                              : FundWalletTokens.transferDisabledLight)
                          : cs.red,
                      borderRadius: BorderRadius.circular(transfer
                          ? FundWalletTokens.transferButtonRadius
                          : FundWalletTokens.packetButtonRadius)),
                  child: isSubmitting
                      ? SizedBox.square(
                          dimension: FundTokens.spinnerSize,
                          child: CircularProgressIndicator(
                              strokeWidth: FundTokens.spinnerStroke,
                              color: AppTokens.onAccent))
                      : Text(
                          hasPending
                              ? _text(
                                  context, '重试原交易', 'Retry original payment')
                              : _text(context, transfer ? '确认' : '塞钱进红包',
                                  transfer ? 'Confirm' : 'Send Red Packet'),
                          style: _walletStyle(context,
                              transfer ? 18 : FundWalletTokens.packetButtonFont,
                              color: transfer && !enabled
                                  ? cs.subText
                                  : AppTokens.onAccent,
                              weight: transfer
                                  ? FontWeight.w700
                                  : FontWeight.w800)),
                ))));
  }

  Widget _notice(BuildContext context,
          {double font = FundWalletTokens.noticeFont}) =>
      Text(
          isMultiple
              ? _text(context, '未领取的红包，将于24小时后发起退款',
                  'Unclaimed red packets will be refunded after 24 hours.')
              : _text(context, '发送成功后直接到账，无需领取。',
                  'Funds are delivered directly after sending.'),
          textAlign: TextAlign.center,
          style: _walletStyle(context, font,
              color: FundPageColors.of(context).subText,
              weight: FontWeight.w400));
  Widget _statusBanner(
    BuildContext context,
  ) {
    final cs = FundPageColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (error != null)
        Padding(
            padding: const EdgeInsets.all(8),
            child: Semantics(
                liveRegion: true,
                child: Text(error!,
                    textAlign: TextAlign.center,
                    style: _walletStyle(context, FundWalletTokens.noticeFont,
                        color: cs.red)))),
      if (error != null && !hasBalances)
        TextButton(
            onPressed: isSubmitting ? null : onReload,
            child: Text(_text(context, '重新加载', 'Reload'))),
      if (!passwordSet && !isLoading)
        TextButton(
            onPressed: isSubmitting ? null : onSetPassword,
            child: Text(_text(
                context, '设置六位支付密码', 'Set a six-digit payment password'))),
    ]);
  }

  Widget _packetBody(
    BuildContext context,
  ) {
    final cs = FundPageColors.of(context);
    return Form(
        key: formKey,
        child: Column(children: [
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final width =
                math.min(constraints.maxWidth, FundTokens.contentMaxWidth) -
                    FundWalletTokens.packetOuter * 2;
            final metrics = _GroupSendMetrics.from(
                Size(width, MediaQuery.sizeOf(context).height));
            return Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: FundTokens.contentMaxWidth),
                    child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(
                            FundWalletTokens.packetOuter,
                            FundWalletTokens.packetTop,
                            FundWalletTokens.packetOuter,
                            FundWalletTokens.packetBottom),
                        children: [
                          if (isLoading)
                            const Center(child: CircularProgressIndicator()),
                          if (isGroup) ...[
                            Align(
                                alignment: Alignment.centerLeft,
                                child: InkWell(
                                    key: const ValueKey('fund-packet-type'),
                                    onTap: isLocked || isLoading
                                        ? null
                                        : onChooseType,
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2.5),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(_bizLabel(context, biz),
                                                  style: _walletStyle(context,
                                                      FundWalletTokens.typeFont,
                                                      color: FundWalletTokens
                                                          .typeColor)),
                                              const SizedBox(width: 3),
                                              const Icon(
                                                  Icons
                                                      .keyboard_arrow_down_rounded,
                                                  color: FundWalletTokens
                                                      .typeColor,
                                                  size: FundWalletTokens
                                                      .typeIcon),
                                            ])))),
                            SizedBox(height: metrics.typeGap),
                            if (isMultiple)
                              _countRow(
                                context,
                              )
                            else
                              _recipientRow(
                                context,
                              ),
                            SizedBox(height: metrics.fieldGap),
                          ],
                          _amountRow(
                            context,
                          ),
                          SizedBox(
                              height: isGroup
                                  ? metrics.fieldGap
                                  : FundWalletTokens.singleFieldGap),
                          _blessingInput(
                            context,
                          ),
                          SizedBox(
                              height: isGroup
                                  ? metrics.payGap
                                  : FundWalletTokens.singlePayLabelGap),
                          if (!isGroup) ...[
                            Text(_text(context, '付款方式', 'Payment Method'),
                                style: _walletStyle(context, 11,
                                    color: cs.subText,
                                    weight: FontWeight.w400)),
                            const SizedBox(
                                height: FundWalletTokens.singlePayCardGap),
                          ],
                          _payCard(
                            context,
                          ),
                          SizedBox(
                              height: isGroup
                                  ? metrics.totalGap
                                  : FundWalletTokens.singleTotalGap),
                          _packetTotal(
                              context,
                              isGroup
                                  ? metrics.totalText
                                  : FundWalletTokens.singleTotalFont,
                              isGroup
                                  ? metrics.coinText
                                  : FundWalletTokens.singleCoinFont),
                          SizedBox(
                              height: isGroup
                                  ? metrics.buttonGap
                                  : FundWalletTokens.singleButtonGap),
                          if (isGroup)
                            Center(
                                child: _sendButton(context,
                                    width: metrics.buttonWidth))
                          else
                            _sendButton(
                              context,
                            ),
                          SizedBox(
                              height: isGroup
                                  ? metrics.noticeGap
                                  : FundWalletTokens.singleNoticeGap),
                          _notice(context,
                              font: isGroup
                                  ? metrics.noticeText
                                  : FundWalletTokens.noticeFont),
                          SizedBox(
                              height: isGroup
                                  ? metrics.bottomPadding
                                  : FundWalletTokens.packetBottom),
                        ])));
          })),
          _statusBanner(
            context,
          ),
        ]));
  }

  Widget _transferBody(BuildContext context) {
    final scale = (MediaQuery.sizeOf(context).width / 375).clamp(.92, 1.0);
    return FundTransferSendForm(
        isGroup: isGroup,
        isLocked: isLocked,
        isLoading: isLoading,
        isSubmitting: isSubmitting,
        hasPending: hasPending,
        currency: currency,
        balance: balance,
        recipientID: recipientID,
        recipientName: recipientName,
        recipientFaceURL: recipientFaceURL,
        formKey: formKey,
        amountInput: _amountField(context, transfer: true),
        notice: _remarkField(context, transfer: true),
        statusBanner: _statusBanner(context),
        submitButton: _sendButton(context,
            width: FundWalletTokens.transferButtonWidth * scale,
            transfer: true),
        onClose: onClose,
        onChooseCurrency: onChooseCurrency,
        onChooseRecipient: onChooseRecipient);
  }

  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    return PopScope(
        canPop: !isSubmitting,
        child: Scaffold(
            backgroundColor: cs.bg,
            resizeToAvoidBottomInset: true,
            appBar: isRedPacket
                ? GlassAppBar(
                    toolbarHeight: kToolbarHeight,
                    leading: IconButton(
                        key: const ValueKey('fund-close'),
                        tooltip:
                            MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: isSubmitting ? null : onClose,
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            color: cs.blue)),
                    backgroundColor: cs.bg,
                    foregroundColor: cs.text,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    surfaceTintColor: FundTokens.transparent,
                    centerTitle: true,
                    title: Text(
                        isGroup
                            ? _text(context, '发送红包', 'Send Red Packet')
                            : _text(context, '普通红包', 'Regular Red Packet'),
                        style:
                            _walletStyle(context, 17, weight: FontWeight.w600)))
                : null,
            body: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: isRedPacket
                    ? _packetBody(
                        context,
                      )
                    : _transferBody(
                        context,
                      ))));
  }
}

/// Direct port of the reference group layout's adaptive geometry.
class _GroupSendMetrics {
  const _GroupSendMetrics(
      {required this.typeGap,
      required this.fieldGap,
      required this.payGap,
      required this.totalGap,
      required this.buttonGap,
      required this.noticeGap,
      required this.totalText,
      required this.coinText,
      required this.buttonWidth,
      required this.noticeText,
      required this.bottomPadding});
  final double typeGap,
      fieldGap,
      payGap,
      totalGap,
      buttonGap,
      noticeGap,
      totalText,
      coinText,
      buttonWidth,
      noticeText,
      bottomPadding;
  factory _GroupSendMetrics.from(Size size) {
    final width = size.width, height = size.height;
    final shortest = math.min(width, height);
    final maxWidth = width > 720 ? math.min(width * .62, 560.0) : width;
    double byH(double value, double min, double max) =>
        (height * value).clamp(min, max).toDouble();
    return _GroupSendMetrics(
        typeGap: byH(.01, 4, 8),
        fieldGap: byH(.02, 7, 12),
        payGap: byH(.024, 9, 15),
        totalGap: byH(.09, 29, 50),
        buttonGap: byH(.04, 14, 22),
        noticeGap: byH(.065, 22, 40),
        totalText: (shortest * .14).clamp(32, 43).toDouble(),
        coinText: (shortest * .082).clamp(18, 26).toDouble(),
        buttonWidth: maxWidth * (width > 720 ? .56 : .52),
        noticeText: (shortest * .042).clamp(9, 12).toDouble(),
        bottomPadding: byH(.035, 10, 18));
  }
}
