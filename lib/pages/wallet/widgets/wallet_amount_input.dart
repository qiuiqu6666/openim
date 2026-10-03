import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'wallet_99chat_tokens.dart';

import '../order/wallet_order.dart';
import 'wallet_page_colors.dart';
import 'wallet_99chat_scale.dart';

/// 转账/红包等金额输入的共享字号体系（逻辑像素，与转账页 `* scale` 一致）。
class WalletAmountTypography {
  WalletAmountTypography._();

  static const double designFontSize = 38;
  static const FontWeight fontWeight = FontWeight.w500;
  static const double lineHeight = 1.2;
  static const String hint = '0';

  static double scale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / 375).clamp(0.92, 1.0);
  }

  static double fontSize(BuildContext context) => designFontSize * scale(context);

  static double minTapHeight(BuildContext context) => 52 * scale(context);

  static TextStyle textStyle(
    BuildContext context, {
    required Color color,
    FontWeight? fontWeight,
  }) {
    return TextStyle(
      fontFamily: AppTokens.fontFamilyOf(context),
      fontFamilyFallback: AppTokens.fontFamilyFallbackOf(context),
      fontSize: fontSize(context),
      fontWeight: fontWeight ?? WalletAmountTypography.fontWeight,
      height: lineHeight,
      color: color,
    );
  }

  static TextStyle hintStyle(BuildContext context, {required Color color}) {
    return textStyle(context, color: color, fontWeight: FontWeight.w400);
  }
}

/// 扩大 TextField 可点击区域，避免 isCollapsed 导致只能点到文字行。
Widget walletTapInputWrapper({
  required Widget child,
  FocusNode? focusNode,
  double? minHeight,
  Alignment alignment = Alignment.centerLeft,
  bool expandWidth = false,
}) {
  Widget content = child;
  if (minHeight != null && minHeight > 0) {
    content = SizedBox(
      height: minHeight,
      width: expandWidth ? double.infinity : null,
      child: Align(
        alignment: alignment,
        child: content,
      ),
    );
  } else if (expandWidth) {
    content = SizedBox(
      width: double.infinity,
      child: content,
    );
  }

  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: focusNode != null ? () => focusNode.requestFocus() : null,
    child: content,
  );
}

class WalletAmountInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final int scale;
  final int maxInt;
  final TextAlign textAlign;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final Color? hintColor;
  final Color? cursorColor;
  final ValueChanged<String>? onChanged;
  final double? minTapHeight;
  final bool? expandWidth;
  final bool useSp;

  const WalletAmountInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.hint = '0.00',
    this.scale = 8,
    this.maxInt = 12,
    this.textAlign = TextAlign.right,
    this.fontSize = 29,
    this.fontWeight = FontWeight.w400,
    this.color,
    this.hintColor,
    this.cursorColor,
    this.onChanged,
    this.minTapHeight = 48,
    this.expandWidth,
    this.useSp = false,
  });

  static InputDecoration plainDecoration({
    required String hint,
    required TextStyle hintStyle,
    EdgeInsetsGeometry contentPadding = EdgeInsets.zero,
    bool collapsed = false,
  }) {
    return InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      filled: false,
      fillColor: Colors.transparent,
      hintText: hint.isEmpty ? null : hint,
      hintStyle: hintStyle,
      counterText: '',
      isDense: true,
      isCollapsed: collapsed,
      contentPadding: contentPadding,
    );
  }

  double _resolveFontSize() => useSp ? fontSize.sp99 : fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final resolvedFontSize = _resolveFontSize();
    final hintStyle = TextStyle(
      fontFamily: AppTokens.fontFamilyOf(context),
      fontFamilyFallback: AppTokens.fontFamilyFallbackOf(context),
      fontSize: resolvedFontSize,
      color: hintColor ?? cs.inputHint,
      fontWeight: FontWeight.w400,
      height: 1.2,
    );
    final alignment = textAlign == TextAlign.right
        ? Alignment.centerRight
        : Alignment.centerLeft;

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: textAlign,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        _AmountFormatter(scale: scale, maxInt: maxInt),
      ],
      onChanged: onChanged,
      cursorColor: cursorColor,
      style: TextStyle(
        fontFamily: AppTokens.fontFamilyOf(context),
        fontFamilyFallback: AppTokens.fontFamilyFallbackOf(context),
        fontSize: resolvedFontSize,
        color: color ?? cs.text,
        fontWeight: fontWeight,
        height: 1.2,
      ),
      decoration: plainDecoration(
        hint: hint,
        hintStyle: hintStyle,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );

    final themedField = cursorColor == null
        ? Material(type: MaterialType.transparency, child: field)
        : Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                cursorColor: cursorColor,
                selectionColor: cursorColor!.withValues(alpha: 0.28),
                selectionHandleColor: cursorColor,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: field),
          );

    return walletTapInputWrapper(
      focusNode: focusNode,
      minHeight: minTapHeight,
      alignment: alignment,
      expandWidth: expandWidth ?? (minTapHeight != null && minTapHeight! > 0),
      child: themedField,
    );
  }
}

class WalletPlainTextInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hint;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final Color? cursorColor;
  final TextAlign textAlign;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final TextInputAction? textInputAction;
  final double? minTapHeight;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool expandWidth;

  const WalletPlainTextInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.hint,
    this.style,
    this.hintStyle,
    this.cursorColor,
    this.textAlign = TextAlign.left,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.maxLength,
    this.maxLengthEnforcement,
    this.textInputAction,
    this.minTapHeight = 48,
    this.maxLines = 1,
    this.onChanged,
    this.expandWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final alignment = switch (textAlign) {
      TextAlign.right => Alignment.centerRight,
      TextAlign.center => Alignment.center,
      _ => Alignment.centerLeft,
    };
    final resolvedStyle = style ??
        const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ).copyWith(color: cs.text);
    final resolvedHintStyle = hintStyle ??
        resolvedStyle.copyWith(
          color: cs.inputHint,
          fontWeight: FontWeight.w400,
        );

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: textAlign,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      maxLengthEnforcement: maxLengthEnforcement,
      textInputAction: textInputAction,
      maxLines: maxLines,
      onChanged: onChanged,
      cursorColor: cursorColor,
      style: resolvedStyle,
      decoration: WalletAmountInput.plainDecoration(
        hint: hint ?? '',
        hintStyle: resolvedHintStyle,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );

    final themedField = cursorColor == null
        ? Material(type: MaterialType.transparency, child: field)
        : Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                cursorColor: cursorColor,
                selectionColor: cursorColor!.withValues(alpha: 0.28),
                selectionHandleColor: cursorColor,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: field),
          );

    return walletTapInputWrapper(
      focusNode: focusNode,
      minHeight: minTapHeight,
      alignment: alignment,
      expandWidth: expandWidth,
      child: themedField,
    );
  }
}

class _AmountFormatter extends TextInputFormatter {
  final int scale;
  final int maxInt;

  const _AmountFormatter({required this.scale, required this.maxInt});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text;
    final cleaned = WalletAmount.clean(raw, scale: scale, maxInt: maxInt);
    if (cleaned == raw) return newValue;

    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
      composing: TextRange.empty,
    );
  }
}
