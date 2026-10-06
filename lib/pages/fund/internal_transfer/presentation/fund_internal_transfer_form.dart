import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/fund_models.dart';
import '../../../group_features/sangong/widgets/app_back_button.dart';
import '../../../mine/settings/widgets/settings_widgets.dart';
import '../data/fund_transfer_recipient_source.dart';
import 'fund_internal_transfer_tokens.dart';
import '../../widgets/fund_page_colors.dart';

/// Account withdrawal presentation. The owner resolves users and handles payment.
class FundInternalTransferForm extends StatelessWidget {
  const FundInternalTransferForm({
    super.key,
    required this.currency,
    required this.accountType,
    this.phoneAreaCode = '+86',
    this.onChooseAreaCode,
    required this.recipientInput,
    required this.amount,
    required this.amountFocus,
    required this.formKey,
    required this.isLocked,
    required this.isLoading,
    required this.isSubmitting,
    required this.canSubmit,
    required this.hasPending,
    required this.passwordSet,
    required this.available,
    required this.arrivalAmount,
    this.recipientName,
    this.recipientFaceURL,
    this.error,
    required this.onEdited,
    required this.onRecipientEdited,
    this.onRecipientSubmitted,
    required this.onChooseAccountType,
    required this.onChooseRecipient,
    required this.onAll,
    required this.onSubmit,
    required this.onReload,
    required this.onSetPassword,
    required this.onClose,
    required this.onHelp,
    required this.onHistory,
    required this.validateAmount,
    required this.validateRecipient,
  });

  final FundCurrency currency;
  final FundTransferAccountType accountType;
  final String phoneAreaCode;
  final VoidCallback? onChooseAreaCode;
  final TextEditingController recipientInput, amount;
  final FocusNode amountFocus;
  final GlobalKey<FormState> formKey;
  final bool isLocked,
      isLoading,
      isSubmitting,
      canSubmit,
      hasPending,
      passwordSet;
  final String available, arrivalAmount;
  final String? recipientName, recipientFaceURL, error;
  final VoidCallback onEdited,
      onRecipientEdited,
      onChooseAccountType,
      onChooseRecipient,
      onAll,
      onSubmit,
      onReload,
      onSetPassword,
      onClose,
      onHelp,
      onHistory;
  final FormFieldValidator<String> validateAmount, validateRecipient;
  final VoidCallback? onRecipientSubmitted;

  bool get _editable => !isLocked && !isLoading;
  String get _coin => currency == FundCurrency.bi99 ? '99币' : currency.code;
  String _text(BuildContext context, String zh, String en) =>
      settingsText(context, zh: zh, en: en);
  String _accountLabel(BuildContext context) => switch (accountType) {
        FundTransferAccountType.uid => 'UID',
        FundTransferAccountType.email => _text(context, '邮箱', 'Email'),
        FundTransferAccountType.phone => _text(context, '手机号', 'Phone number'),
        FundTransferAccountType.account => _text(context, '99号', '99Chat ID'),
      };
  String _recipientHint(BuildContext context) => switch (accountType) {
        FundTransferAccountType.uid =>
          _text(context, '请填写收款人UID', 'Enter recipient UID'),
        FundTransferAccountType.email =>
          _text(context, '请填写收款人邮箱', 'Enter recipient email'),
        FundTransferAccountType.phone =>
          _text(context, '请填写收款人手机号', 'Enter recipient phone number'),
        FundTransferAccountType.account =>
          _text(context, '请填写收款人99号', 'Enter recipient 99Chat ID'),
      };

  TextStyle _style(BuildContext context, double size,
          {Color? color, FontWeight weight = FontWeight.w400}) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: size,
          height: 1.3,
          fontWeight: weight,
          color: color ?? FundPageColors.of(context).text);

  Widget _label(BuildContext context, String label) => Text(label,
      style: _style(context, FundInternalTransferTokens.labelFont,
          weight: FontWeight.w600));

  InputDecoration _inputDecoration(BuildContext context, String hint,
      {Widget? suffix, Widget? prefix}) {
    final colors = FundPageColors.of(context);
    return InputDecoration(
        hintText: hint,
        hintStyle: _style(context, FundInternalTransferTokens.inputFont,
            color: colors.inputHint),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: true,
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
            vertical: FundInternalTransferTokens.fieldPadding),
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(
            minWidth: 0, minHeight: FundInternalTransferTokens.targetMinSize),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(
            minWidth: FundInternalTransferTokens.targetMinSize,
            minHeight: FundInternalTransferTokens.targetMinSize));
  }

  Widget _areaCode(BuildContext context) {
    final colors = FundPageColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
          button: true,
          label: _text(context, '选择手机号区号', 'Choose phone calling code'),
          value: phoneAreaCode,
          child: InkWell(
              key: const ValueKey('internal-transfer-area-code'),
              borderRadius:
                  BorderRadius.circular(FundInternalTransferTokens.fieldRadius),
              onTap: _editable ? onChooseAreaCode : null,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minHeight: FundInternalTransferTokens.targetMinSize,
                      minWidth: FundInternalTransferTokens.targetMinSize),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(phoneAreaCode,
                        style: _style(
                            context, FundInternalTransferTokens.inputFont)),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: colors.subText,
                        size: FundInternalTransferTokens.iconSize),
                  ])))),
      Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: FundInternalTransferTokens.smallGap),
          child: SizedBox(
              height: FundInternalTransferTokens.areaCodeDividerHeight,
              child: VerticalDivider(
                  width: FundInternalTransferTokens.areaCodeDividerWidth,
                  thickness: FundInternalTransferTokens.areaCodeDividerWidth,
                  color: colors.line))),
    ]);
  }

  Widget _fieldSurface(BuildContext context, Widget child) => Container(
      constraints: const BoxConstraints(
          minHeight: FundInternalTransferTokens.fieldMinHeight),
      padding: const EdgeInsets.symmetric(
          horizontal: FundInternalTransferTokens.fieldPadding),
      decoration: BoxDecoration(
          color: FundPageColors.of(context).inputFill,
          borderRadius:
              BorderRadius.circular(FundInternalTransferTokens.fieldRadius)),
      child: child);

  Widget _header(BuildContext context) {
    final colors = FundPageColors.of(context);
    return ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: FundInternalTransferTokens.headerMinHeight),
        child: Row(children: [
          // Match the two trailing action slots so the title tracks page center.
          SizedBox(
              width: FundInternalTransferTokens.headerSideWidth,
              child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox.square(
                      dimension: FundInternalTransferTokens.targetMinSize,
                      child: AbsorbPointer(
                          absorbing: isSubmitting,
                          child: AppBackButton(
                              key: const ValueKey('fund-close'),
                              onPressed: onClose))))),
          Expanded(
              child: Text(_text(context, '提现 $_coin', 'Withdraw $_coin'),
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: _style(context, FundInternalTransferTokens.titleFont,
                      weight: FontWeight.w700))),
          SizedBox.square(
              dimension: FundInternalTransferTokens.targetMinSize,
              child: IconButton(
                  key: const ValueKey('internal-transfer-help'),
                  tooltip: _text(context, '提现说明', 'Withdrawal help'),
                  onPressed: isSubmitting ? null : onHelp,
                  icon: Icon(Icons.help_outline_rounded,
                      size: FundInternalTransferTokens.iconSize,
                      color: colors.text))),
          SizedBox.square(
              dimension: FundInternalTransferTokens.targetMinSize,
              child: IconButton(
                  key: const ValueKey('internal-transfer-history'),
                  tooltip: _text(context, '历史记录', 'History'),
                  onPressed: isSubmitting ? null : onHistory,
                  icon: Icon(Icons.history_rounded,
                      size: FundInternalTransferTokens.iconSize,
                      color: colors.text))),
        ]));
  }

  Widget _accountType(BuildContext context) {
    final colors = FundPageColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context, _text(context, '账号类型', 'Account type')),
      const SizedBox(height: FundInternalTransferTokens.labelGap),
      _fieldSurface(
          context,
          InkWell(
              key: const ValueKey('internal-transfer-account-type'),
              borderRadius:
                  BorderRadius.circular(FundInternalTransferTokens.fieldRadius),
              onTap: _editable ? onChooseAccountType : null,
              child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: FundInternalTransferTokens.fieldPadding),
                  child: Row(children: [
                    Expanded(
                        child: Text(_accountLabel(context),
                            style: _style(
                                context, FundInternalTransferTokens.inputFont,
                                weight: FontWeight.w600))),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: colors.subText,
                        size: FundInternalTransferTokens.iconSize),
                  ])))),
    ]);
  }

  Widget _recipient(BuildContext context) {
    final colors = FundPageColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context, _accountLabel(context)),
      const SizedBox(height: FundInternalTransferTokens.labelGap),
      _fieldSurface(
          context,
          TextFormField(
              key: const ValueKey('internal-transfer-recipient'),
              controller: recipientInput,
              enabled: _editable,
              autocorrect: false,
              keyboardType: switch (accountType) {
                FundTransferAccountType.email => TextInputType.emailAddress,
                FundTransferAccountType.phone => TextInputType.phone,
                FundTransferAccountType.uid => TextInputType.text,
                FundTransferAccountType.account => TextInputType.text,
              },
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) {
                onRecipientSubmitted?.call();
                amountFocus.requestFocus();
              },
              cursorColor: colors.inputCursor,
              style: _style(context, FundInternalTransferTokens.inputFont),
              decoration: _inputDecoration(
                  context,
                  recipientName?.isNotEmpty == true &&
                          recipientInput.text.isEmpty
                      ? _text(context, '已选择收款人', 'Recipient selected')
                      : _recipientHint(context),
                  prefix: accountType == FundTransferAccountType.phone
                      ? _areaCode(context)
                      : null,
                  suffix: IconButton(
                      key: const ValueKey('internal-transfer-contacts'),
                      tooltip: _text(context, '选择收款人', 'Select recipient'),
                      onPressed: _editable ? onChooseRecipient : null,
                      icon: Icon(Icons.account_circle_outlined,
                          color: colors.subText,
                          size: FundInternalTransferTokens.iconSize))),
              validator: validateRecipient,
              onChanged: (_) => onRecipientEdited())),
      if (recipientName?.isNotEmpty == true) ...[
        const SizedBox(height: FundInternalTransferTokens.smallGap),
        Row(children: [
          AvatarView(
              width: FundInternalTransferTokens.recipientAvatar,
              height: FundInternalTransferTokens.recipientAvatar,
              url: recipientFaceURL,
              text: recipientName,
              isCircle: true),
          const SizedBox(width: FundInternalTransferTokens.smallGap),
          Expanded(
              child: Text(
                  _text(context, '收款人：$recipientName',
                      'Recipient: $recipientName'),
                  style: _style(context, FundInternalTransferTokens.detailFont,
                      color: colors.subText))),
        ]),
      ],
    ]);
  }

  Widget _amount(BuildContext context) {
    final colors = FundPageColors.of(context);
    final min = currency.decimals == 2 ? '0.01' : '0.000001';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context, _text(context, '提现数量', 'Withdrawal amount')),
      const SizedBox(height: FundInternalTransferTokens.labelGap),
      _fieldSurface(
          context,
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
                child: TextFormField(
                    key: const ValueKey('fund-amount'),
                    controller: amount,
                    focusNode: amountFocus,
                    enabled: _editable,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    cursorColor: colors.inputCursor,
                    style:
                        _style(context, FundInternalTransferTokens.inputFont),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: _inputDecoration(
                        context, _text(context, '最少 $min', 'Minimum $min')),
                    validator: validateAmount,
                    onChanged: (_) => onEdited())),
            const SizedBox(width: FundInternalTransferTokens.smallGap),
            Text(_coin,
                style: _style(context, FundInternalTransferTokens.inputFont)),
            TextButton(
                key: const ValueKey('internal-transfer-all'),
                onPressed: _editable ? onAll : null,
                style: TextButton.styleFrom(
                    foregroundColor: colors.dark
                        ? Color.lerp(AppTokens.success, colors.text, .18)
                        : AppTokens.success,
                    minimumSize: const Size(
                        FundInternalTransferTokens.targetMinSize,
                        FundInternalTransferTokens.targetMinSize)),
                child: Text(_text(context, '全部', 'All'),
                    style: _style(context, FundInternalTransferTokens.inputFont,
                        color: colors.dark
                            ? Color.lerp(AppTokens.success, colors.text, .18)
                            : AppTokens.success,
                        weight: FontWeight.w600))),
          ])),
      const SizedBox(height: FundInternalTransferTokens.smallGap),
      Text(
          _text(
              context, '可用：$available $_coin', 'Available: $available $_coin'),
          style: _style(context, FundInternalTransferTokens.detailFont)),
    ]);
  }

  Widget _notices(BuildContext context) {
    final colors = FundPageColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hasPending)
        Padding(
            padding:
                const EdgeInsets.only(top: FundInternalTransferTokens.labelGap),
            child: Text(
                _text(context, '有一笔待确认的转账，请继续确认支付结果。',
                    'A transfer is pending. Continue to confirm the result.'),
                style: _style(context, FundInternalTransferTokens.detailFont,
                    color: colors.warningText))),
      if (error?.isNotEmpty == true)
        Padding(
            padding:
                const EdgeInsets.only(top: FundInternalTransferTokens.labelGap),
            child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: FundInternalTransferTokens.smallGap,
                children: [
                  Text(error!,
                      style: _style(
                          context, FundInternalTransferTokens.detailFont,
                          color: colors.red)),
                  TextButton(
                      onPressed: isLoading || isSubmitting ? null : onReload,
                      child: Text(_text(context, '重试', 'Retry'))),
                ])),
      if (!passwordSet && !isLoading)
        TextButton(
            onPressed: isSubmitting ? null : onSetPassword,
            child: Text(_text(context, '设置支付密码', 'Set payment password'))),
    ]);
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final colors = FundPageColors.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          child: Text(label,
              style: _style(context, FundInternalTransferTokens.detailFont,
                  color: colors.subText))),
      const SizedBox(width: FundInternalTransferTokens.smallGap),
      Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: _style(context, FundInternalTransferTokens.inputFont,
                  weight: FontWeight.w600))),
    ]);
  }

  Widget _footer(BuildContext context) {
    final colors = FundPageColors.of(context);
    return Padding(
        padding: const EdgeInsets.only(
            top: FundInternalTransferTokens.footerGap,
            bottom: FundInternalTransferTokens.footerBottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _summaryRow(context, _text(context, '到账数量', 'Arrival amount'),
              '$arrivalAmount $_coin'),
          const SizedBox(height: FundInternalTransferTokens.smallGap),
          _summaryRow(
              context, _text(context, '网络手续费', 'Network fee'), '0.00 $_coin'),
          const SizedBox(height: FundInternalTransferTokens.footerGap),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                  key: const ValueKey('internal-transfer-submit'),
                  onPressed: canSubmit && !isLoading && !isSubmitting
                      ? onSubmit
                      : null,
                  style: FilledButton.styleFrom(
                      backgroundColor: colors.text,
                      foregroundColor: colors.card,
                      disabledBackgroundColor: colors.disabledButton,
                      disabledForegroundColor: colors.subText,
                      minimumSize: const Size.fromHeight(
                          FundInternalTransferTokens.buttonMinHeight),
                      padding: const EdgeInsets.symmetric(
                          vertical: FundInternalTransferTokens.fieldPadding),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              FundInternalTransferTokens.fieldRadius))),
                  child: Text(
                      isSubmitting
                          ? _text(context, '正在确认…', 'Confirming…')
                          : hasPending
                              ? _text(context, '继续支付', 'Continue payment')
                              : _text(context, '提现', 'Withdraw'),
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontSize: FundInternalTransferTokens.buttonFont,
                          color: canSubmit && !isLoading && !isSubmitting
                              ? colors.card
                              : colors.subText,
                          fontWeight: FontWeight.w600)))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final colors = FundPageColors.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppSystemBars.styleFor(colors.card),
        child: Scaffold(
            key: const ValueKey('internal-transfer-form'),
            backgroundColor: colors.card,
            body: SafeArea(
                child: Form(
                    key: formKey,
                    child: Column(children: [
                      _header(context),
                      if (isLoading) const LinearProgressIndicator(),
                      Expanded(
                          child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxWidth: FundInternalTransferTokens
                                          .pageMaxWidth),
                                  child: CustomScrollView(
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      slivers: [
                                        SliverPadding(
                                            padding: const EdgeInsets.fromLTRB(
                                                FundInternalTransferTokens
                                                    .pageMargin,
                                                FundInternalTransferTokens
                                                    .topGap,
                                                FundInternalTransferTokens
                                                    .pageMargin,
                                                0),
                                            sliver: SliverToBoxAdapter(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  _accountType(context),
                                                  const SizedBox(
                                                      height:
                                                          FundInternalTransferTokens
                                                              .sectionGap),
                                                  _recipient(context),
                                                  const SizedBox(
                                                      height:
                                                          FundInternalTransferTokens
                                                              .sectionGap),
                                                  _amount(context),
                                                  _notices(context),
                                                ]))),
                                        SliverPadding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal:
                                                    FundInternalTransferTokens
                                                        .pageMargin),
                                            sliver: SliverFillRemaining(
                                                hasScrollBody: false,
                                                child: Align(
                                                    alignment:
                                                        Alignment.bottomCenter,
                                                    child: _footer(context)))),
                                      ])))),
                    ])))));
  }
}
