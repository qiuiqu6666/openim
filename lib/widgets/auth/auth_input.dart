import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import 'auth_tokens.dart';

/// An auth style preset for InputBox; editing and verification remain shared.
class AuthInput extends StatelessWidget {
  const AuthInput({
    super.key,
    required this.label,
    required this.controller,
    this.type = InputBoxType.account,
    this.hintText,
    this.code = '+86',
    this.onAreaCode,
    this.onSendVerificationCode,
    this.focusNode,
    this.inputFormatters,
    this.keyBoardType,
    this.autofillHints,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.formatHintText,
    this.enabled = true,
    this.leadingIcon,
  });

  final String label;
  final TextEditingController controller;
  final InputBoxType type;
  final String? hintText;
  final String code;
  final VoidCallback? onAreaCode;
  final Future<bool> Function()? onSendVerificationCode;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyBoardType;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode autovalidateMode;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? formatHintText;
  final bool enabled;
  final IconData? leadingIcon;

  IconData get _icon =>
      leadingIcon ??
      switch (type) {
        InputBoxType.password => CupertinoIcons.lock,
        InputBoxType.verificationCode => CupertinoIcons.number,
        InputBoxType.invitationCode => CupertinoIcons.ticket,
        _ => keyBoardType == TextInputType.emailAddress
            ? CupertinoIcons.mail
            : CupertinoIcons.person,
      };

  @override
  Widget build(BuildContext context) => InputBox(
        label: label,
        controller: controller,
        type: type,
        hintText: hintText,
        code: code,
        onAreaCode: onAreaCode,
        onSendVerificationCode: onSendVerificationCode,
        obscureText: type == InputBoxType.password,
        focusNode: focusNode,
        inputFormatters: inputFormatters,
        keyBoardType: keyBoardType,
        autofillHints: autofillHints,
        validator: validator,
        autovalidateMode: autovalidateMode,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        formatHintText: formatHintText,
        formatHintStyle: AuthTokens.body(context),
        enabled: enabled,
        filled: true,
        showLabel: false,
        minHeight: AuthTokens.controlHeight,
        iconSize: AuthTokens.welcomeInputIconSize,
        borderRadius: AuthTokens.welcomeInputRadius,
        areaCodeDividerHeight: AuthTokens.welcomeInputDividerHeight,
        fillColor: AuthTokens.welcomeInputFill(context),
        borderColor: AuthTokens.welcomeInputBorder(context),
        textStyle: AuthTokens.welcomeInputText(context),
        codeStyle: AuthTokens.welcomeInputText(context),
        hintStyle: AuthTokens.welcomeInputHint(context),
        leadingIcon: _icon,
        obscuredIcon: CupertinoIcons.eye_slash,
        revealedIcon: CupertinoIcons.eye,
      );
}
