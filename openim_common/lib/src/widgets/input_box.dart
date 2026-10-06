import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart' hide VerifyCodedButton;

import 'input_box/verify_coded_button.dart';

export 'input_box/verify_coded_button.dart' show VerifyCodedButton;

enum InputBoxType {
  phone,
  account,
  password,
  verificationCode,
  invitationCode,
}

class InputBox extends StatefulWidget {
  const InputBox.phone({
    super.key,
    required this.label,
    required this.code,
    this.onAreaCode,
    this.controller,
    this.focusNode,
    this.labelStyle,
    this.textStyle,
    this.codeStyle,
    this.hintStyle,
    this.formatHintStyle,
    this.hintText,
    this.formatHintText,
    this.margin,
    this.inputFormatters,
    this.keyBoardType,
    this.filled = false,
    this.showLabel = true,
    this.leadingIcon,
    this.fillColor,
    this.borderColor,
    this.iconSize,
    this.borderRadius,
    this.areaCodeDividerHeight,
    this.obscuredIcon,
    this.revealedIcon,
    this.minHeight = AppTokens.listItemHeight,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.autofillHints,
    this.enabled = true,
  })  : obscureText = false,
        type = InputBoxType.phone,
        arrowColor = null,
        clearBtnColor = null,
        onSendVerificationCode = null;

  const InputBox.account({
    super.key,
    required this.label,
    required this.code,
    this.onAreaCode,
    this.controller,
    this.focusNode,
    this.labelStyle,
    this.textStyle,
    this.codeStyle,
    this.hintStyle,
    this.formatHintStyle,
    this.hintText,
    this.formatHintText,
    this.margin,
    this.inputFormatters,
    this.keyBoardType,
    this.filled = false,
    this.showLabel = true,
    this.leadingIcon,
    this.fillColor,
    this.borderColor,
    this.iconSize,
    this.borderRadius,
    this.areaCodeDividerHeight,
    this.obscuredIcon,
    this.revealedIcon,
    this.minHeight = AppTokens.listItemHeight,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.autofillHints,
    this.enabled = true,
  })  : obscureText = false,
        type = InputBoxType.account,
        arrowColor = null,
        clearBtnColor = null,
        onSendVerificationCode = null;

  const InputBox.password({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.labelStyle,
    this.textStyle,
    this.hintStyle,
    this.formatHintStyle,
    this.hintText,
    this.formatHintText,
    this.margin,
    this.inputFormatters,
    this.keyBoardType,
    this.filled = false,
    this.showLabel = true,
    this.leadingIcon,
    this.fillColor,
    this.borderColor,
    this.iconSize,
    this.borderRadius,
    this.areaCodeDividerHeight,
    this.obscuredIcon,
    this.revealedIcon,
    this.minHeight = AppTokens.listItemHeight,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.autofillHints,
    this.enabled = true,
  })  : obscureText = true,
        type = InputBoxType.password,
        codeStyle = null,
        code = '',
        arrowColor = null,
        clearBtnColor = null,
        onSendVerificationCode = null,
        onAreaCode = null;

  const InputBox.verificationCode({
    super.key,
    required this.label,
    this.onSendVerificationCode,
    this.controller,
    this.focusNode,
    this.labelStyle,
    this.textStyle,
    this.hintStyle,
    this.formatHintStyle,
    this.hintText,
    this.formatHintText,
    this.margin,
    this.inputFormatters,
    this.keyBoardType,
    this.filled = false,
    this.showLabel = true,
    this.leadingIcon,
    this.fillColor,
    this.borderColor,
    this.iconSize,
    this.borderRadius,
    this.areaCodeDividerHeight,
    this.obscuredIcon,
    this.revealedIcon,
    this.minHeight = AppTokens.listItemHeight,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.autofillHints,
    this.enabled = true,
  })  : obscureText = false,
        type = InputBoxType.verificationCode,
        code = '',
        codeStyle = null,
        onAreaCode = null,
        arrowColor = null,
        clearBtnColor = null;

  const InputBox.invitationCode({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.labelStyle,
    this.textStyle,
    this.formatHintStyle,
    this.hintStyle,
    this.hintText,
    this.formatHintText,
    this.margin,
    this.inputFormatters,
    this.keyBoardType,
    this.filled = false,
    this.showLabel = true,
    this.leadingIcon,
    this.fillColor,
    this.borderColor,
    this.iconSize,
    this.borderRadius,
    this.areaCodeDividerHeight,
    this.obscuredIcon,
    this.revealedIcon,
    this.minHeight = AppTokens.listItemHeight,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.autofillHints,
    this.enabled = true,
  })  : obscureText = false,
        type = InputBoxType.invitationCode,
        code = '',
        codeStyle = null,
        onAreaCode = null,
        onSendVerificationCode = null,
        arrowColor = null,
        clearBtnColor = null;

  const InputBox({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.labelStyle,
    this.textStyle,
    this.hintStyle,
    this.codeStyle,
    this.formatHintStyle,
    this.code = '+86',
    this.hintText,
    this.formatHintText,
    this.arrowColor,
    this.clearBtnColor,
    this.obscureText = false,
    this.type = InputBoxType.account,
    this.onAreaCode,
    this.onSendVerificationCode,
    this.margin,
    this.inputFormatters,
    this.keyBoardType,
    this.filled = false,
    this.showLabel = true,
    this.leadingIcon,
    this.fillColor,
    this.borderColor,
    this.iconSize,
    this.borderRadius,
    this.areaCodeDividerHeight,
    this.obscuredIcon,
    this.revealedIcon,
    this.minHeight = AppTokens.listItemHeight,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.autofillHints,
    this.enabled = true,
  });
  final TextStyle? labelStyle;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final TextStyle? codeStyle;
  final TextStyle? formatHintStyle;
  final String code;
  final String label;
  final String? hintText;
  final String? formatHintText;
  final Color? arrowColor;
  final Color? clearBtnColor;
  final bool obscureText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputBoxType type;
  final Function()? onAreaCode;
  final Future<bool> Function()? onSendVerificationCode;
  final EdgeInsetsGeometry? margin;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyBoardType;
  final bool filled;
  final bool showLabel;

  /// Optional prefix icon for filled inputs without an area code.
  final IconData? leadingIcon;

  /// Optional filled-input surface and outline colors.
  final Color? fillColor;
  final Color? borderColor;

  /// Optional filled-input icon geometry and password visibility icons.
  final double? iconSize;
  final double? borderRadius;
  final double? areaCodeDividerHeight;
  final IconData? obscuredIcon;
  final IconData? revealedIcon;

  /// Minimum filled-input height; legacy input sizing remains unchanged.
  final double minHeight;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode autovalidateMode;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  State<InputBox> createState() => _InputBoxState();
}

class _InputBoxState extends State<InputBox> {
  late bool _obscureText;
  late TextEditingController _controller;
  bool _showClearBtn = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    _controller = widget.controller ?? TextEditingController();
    _showClearBtn = _controller.text.isNotEmpty;
    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant InputBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final previousValue = _controller.value;
      _controller.removeListener(_onChanged);
      if (oldWidget.controller == null) _controller.dispose();
      _controller =
          widget.controller ?? TextEditingController.fromValue(previousValue);
      _controller.addListener(_onChanged);
      _showClearBtn = _controller.text.isNotEmpty;
    }
    if (oldWidget.obscureText != widget.obscureText ||
        oldWidget.type != widget.type) {
      _obscureText = widget.obscureText;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final showClearBtn = _controller.text.isNotEmpty;
    if (!mounted || showClearBtn == _showClearBtn) return;
    setState(() {
      _showClearBtn = showClearBtn;
    });
  }

  void _toggleEye() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filled) return _buildFilled(context);
    return Container(
      margin: widget.margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showLabel) ...[
            ExcludeSemantics(
              child: Text(
                widget.label,
                style: widget.labelStyle ?? Styles.ts_8E9AB0_12sp,
              ),
            ),
            6.verticalSpace,
          ],
          Container(
            height: 42.h,
            padding: EdgeInsets.only(left: 12.w, right: 8.w),
            decoration: BoxDecoration(
              border: Border.all(color: Styles.c_E8EAEF, width: 1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.type == InputBoxType.phone ||
                    widget.onAreaCode != null)
                  _areaCodeView,
                _textField,
                _clearBtn,
                _eyeBtn,
                if (widget.type == InputBoxType.verificationCode)
                  VerifyCodedButton(
                    onTapCallback: widget.onSendVerificationCode,
                    enabled: widget.enabled,
                  ),
              ],
            ),
          ),
          if (null != widget.formatHintText)
            Padding(
              padding: EdgeInsets.only(top: 5.h),
              child: widget.formatHintText!.toText
                ..style = (widget.formatHintStyle ?? Styles.ts_8E9AB0_12sp),
            ),
        ],
      ),
    );
  }

  Widget get _textField => Expanded(
        child: Semantics(
          label: widget.label,
          child: TextFormField(
            controller: _controller,
            keyboardType: _textInputType,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onSubmitted,
            validator: widget.validator,
            autovalidateMode: widget.autovalidateMode,
            autofillHints: widget.autofillHints,
            enabled: widget.enabled,
            style: widget.textStyle ?? Styles.ts_0C1C33_17sp,
            autofocus: false,
            obscureText: _obscureText,
            focusNode: widget.focusNode,
            inputFormatters: _inputFormatters,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: widget.hintStyle ?? Styles.ts_8E9AB0_17sp,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
          ),
        ),
      );

  Widget get _areaCodeView => GestureDetector(
        onTap: widget.enabled ? widget.onAreaCode : null,
        behavior: HitTestBehavior.translucent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.code,
              style: widget.codeStyle ?? Styles.ts_0C1C33_17sp,
            ),
            8.horizontalSpace,
            ImageRes.downArrow.toImage
              ..width = 8.49.w
              ..height = 8.49.h,
            Container(
              width: 1.w,
              height: 26.h,
              margin: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: Styles.c_E8EAEF,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ],
        ),
      );

  Widget get _clearBtn => Visibility(
        visible: _showClearBtn,
        child: GestureDetector(
          onTap: widget.enabled ? _controller.clear : null,
          behavior: HitTestBehavior.translucent,
          child: ImageRes.clearText.toImage
            ..width = 24.w
            ..height = 24.h,
        ),
      );

  Widget get _eyeBtn => Visibility(
        visible: widget.type == InputBoxType.password,
        child: GestureDetector(
          onTap: widget.enabled ? _toggleEye : null,
          behavior: HitTestBehavior.translucent,
          child: (_obscureText
              ? ImageRes.eyeClose.toImage
              : ImageRes.eyeOpen.toImage)
            ..width = 24.w
            ..height = 24.h,
        ),
      );

  bool get _isPhone =>
      widget.type == InputBoxType.phone || widget.onAreaCode != null;

  bool get _allowsTextCorrection {
    if (_isPhone ||
        widget.type == InputBoxType.password ||
        widget.type == InputBoxType.verificationCode ||
        _textInputType == TextInputType.phone ||
        _textInputType == TextInputType.emailAddress ||
        _textInputType == TextInputType.visiblePassword) {
      return false;
    }
    const authenticationHints = {
      AutofillHints.username,
      AutofillHints.newUsername,
      AutofillHints.email,
      AutofillHints.password,
      AutofillHints.newPassword,
      AutofillHints.oneTimeCode,
      AutofillHints.telephoneNumber,
      AutofillHints.telephoneNumberNational,
      AutofillHints.telephoneNumberCountryCode,
    };
    return !(widget.autofillHints?.any(authenticationHints.contains) ?? false);
  }

  List<TextInputFormatter> get _inputFormatters => [
        if (_isPhone || widget.type == InputBoxType.verificationCode)
          FilteringTextInputFormatter.digitsOnly,
        ...?widget.inputFormatters,
      ];

  Widget _buildFilled(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inputStyle = widget.textStyle ??
        theme.textTheme.bodyLarge?.copyWith(
          color: widget.enabled
              ? colors.onSurface
              : colors.onSurface.withValues(alpha: .38),
        );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(widget.borderRadius ?? AppTokens.rLg),
      borderSide:
          BorderSide(color: widget.borderColor ?? colors.outlineVariant),
    );
    final hasSuffix = widget.type == InputBoxType.password ||
        widget.type == InputBoxType.verificationCode ||
        _showClearBtn;
    return Padding(
      padding: widget.margin ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showLabel) ...[
            ExcludeSemantics(
              child: Text(
                widget.label,
                style: widget.labelStyle ??
                    theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurface,
                      fontSize: AppTokens.captionFontSize,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(height: AppTokens.s3),
          ],
          Semantics(
            label: widget.label,
            child: TextFormField(
              controller: _controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              keyboardType: _textInputType,
              textInputAction: widget.textInputAction,
              onFieldSubmitted: widget.onSubmitted,
              validator: widget.validator,
              autovalidateMode: widget.autovalidateMode,
              autofillHints: widget.autofillHints,
              inputFormatters: _inputFormatters,
              obscureText: _obscureText,
              autocorrect: _allowsTextCorrection,
              enableSuggestions: _allowsTextCorrection,
              style: inputStyle,
              decoration: InputDecoration(
                filled: true,
                fillColor: widget.fillColor ??
                    colors.surfaceContainerHighest.withValues(
                      alpha: theme.brightness == Brightness.dark ? .45 : .55,
                    ),
                hintText: widget.hintText,
                hintStyle: widget.hintStyle ??
                    theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                helperText: widget.formatHintText,
                helperStyle: widget.formatHintStyle ??
                    theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                helperMaxLines: 3,
                errorMaxLines: 3,
                constraints: BoxConstraints(minHeight: widget.minHeight),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTokens.s5,
                  vertical: widget.minHeight < AppTokens.listItemHeight
                      ? AppTokens.s4
                      : AppTokens.s5,
                ),
                border: border,
                enabledBorder: border,
                disabledBorder: border.copyWith(
                  borderSide: BorderSide(
                    color: (widget.borderColor ?? colors.outlineVariant)
                        .withValues(alpha: .5),
                  ),
                ),
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
                errorBorder: border.copyWith(
                  borderSide: BorderSide(color: colors.error),
                ),
                focusedErrorBorder: border.copyWith(
                  borderSide: BorderSide(color: colors.error, width: 1.5),
                ),
                prefixIcon: _isPhone
                    ? _filledAreaCode(context)
                    : widget.leadingIcon != null
                        ? Icon(
                            widget.leadingIcon,
                            color: widget.enabled
                                ? colors.onSurfaceVariant
                                : colors.onSurface.withValues(alpha: .38),
                            size: widget.iconSize ?? AppTokens.chevronSize,
                          )
                        : null,
                prefixIconConstraints:
                    const BoxConstraints(minHeight: 48, minWidth: 48),
                suffixIcon: hasSuffix ? _filledSuffix(context) : null,
                suffixIconConstraints:
                    const BoxConstraints(minHeight: 48, minWidth: 48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filledAreaCode(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final code = Text(
      widget.code,
      style: widget.codeStyle ??
          theme.textTheme.bodyLarge?.copyWith(color: colors.onSurface),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onAreaCode != null)
          TextButton(
            onPressed: widget.enabled ? widget.onAreaCode : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                code,
                const SizedBox(width: AppTokens.s2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: widget.iconSize ?? AppTokens.s6,
                  color: widget.arrowColor ?? colors.onSurfaceVariant,
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
            child: code,
          ),
        Container(
          width: 1,
          height: widget.areaCodeDividerHeight ?? AppTokens.s7,
          margin: const EdgeInsets.only(right: AppTokens.s4),
          color: colors.outlineVariant,
        ),
      ],
    );
  }

  Widget _filledSuffix(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chinese =
        (Get.locale ?? Localizations.localeOf(context)).languageCode == 'zh';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.type == InputBoxType.password)
          IconButton(
            onPressed: widget.enabled ? _toggleEye : null,
            tooltip: _obscureText
                ? (chinese ? '显示密码' : 'Show password')
                : (chinese ? '隐藏密码' : 'Hide password'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            visualDensity: VisualDensity.standard,
            color: colors.onSurfaceVariant,
            icon: Icon(
              _obscureText
                  ? widget.obscuredIcon ?? Icons.visibility_off_outlined
                  : widget.revealedIcon ?? Icons.visibility_outlined,
              size: widget.iconSize,
            ),
          )
        else if (widget.type == InputBoxType.verificationCode)
          VerifyCodedButton(
            onTapCallback: widget.onSendVerificationCode,
            themed: true,
            enabled: widget.enabled,
          )
        else if (_showClearBtn)
          IconButton(
            onPressed: widget.enabled ? _controller.clear : null,
            tooltip: chinese ? '清空' : 'Clear',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            visualDensity: VisualDensity.standard,
            color: widget.clearBtnColor ?? colors.onSurfaceVariant,
            icon: Icon(Icons.cancel_outlined, size: widget.iconSize),
          ),
      ],
    );
  }

  TextInputType? get _textInputType {
    if (widget.keyBoardType != null) {
      return widget.keyBoardType;
    }
    if (_isPhone) return TextInputType.phone;
    TextInputType? keyboardType;
    switch (widget.type) {
      case InputBoxType.phone:
        keyboardType = TextInputType.phone;
        break;
      case InputBoxType.account:
        keyboardType = TextInputType.text;
        break;
      case InputBoxType.password:
        keyboardType = TextInputType.text;
        break;
      case InputBoxType.verificationCode:
        keyboardType = TextInputType.number;
        break;
      case InputBoxType.invitationCode:
        keyboardType = TextInputType.text;
        break;
    }
    return keyboardType;
  }
}
