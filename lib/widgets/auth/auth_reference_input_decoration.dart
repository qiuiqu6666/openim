import 'package:flutter/material.dart';

import 'auth_reference_tokens.dart';

/// Lets Material animate the label and cut its gap in the field outline.
InputDecoration authReferenceInputDecoration({
  required String hint,
  required TextStyle hintStyle,
  required bool focused,
  required bool enabled,
  required EdgeInsets contentPadding,
  String? label,
  String? errorText,
  bool showBorder = true,
  Widget? prefix,
  Widget? suffix,
}) {
  final invalid = errorText?.trim().isNotEmpty ?? false;
  final outlined = label != null && showBorder;
  InputBorder border(Color color, double width) => outlined
      ? OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg),
          borderSide: BorderSide(color: color, width: width),
        )
      : InputBorder.none;
  final normalBorder = border(
    invalid ? AuthReferenceTokens.error : AuthReferenceTokens.fieldBorder,
    AuthReferenceTokens.fieldBorderWidth,
  );
  return InputDecoration(
    filled: label != null,
    fillColor: AuthReferenceTokens.fieldFill,
    labelText: label,
    labelStyle: hintStyle,
    floatingLabelStyle: hintStyle.copyWith(
      color: invalid
          ? AuthReferenceTokens.error
          : focused && enabled
              ? AuthReferenceTokens.brand500
              : hintStyle.color,
    ),
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    hintText: hint,
    hintStyle: hintStyle,
    border: normalBorder,
    enabledBorder: normalBorder,
    disabledBorder: normalBorder,
    focusedBorder: border(
      invalid ? AuthReferenceTokens.error : AuthReferenceTokens.brand500,
      AuthReferenceTokens.focusedFieldBorderWidth,
    ),
    counterText: '',
    contentPadding: contentPadding,
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(
      minWidth: AuthReferenceTokens.tapTarget,
      minHeight: AuthReferenceTokens.tapTarget,
    ),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(
      minWidth: AuthReferenceTokens.tapTarget,
      minHeight: AuthReferenceTokens.tapTarget,
    ),
  );
}
