import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../../../widgets/auth/auth_tokens.dart';

/// Six visual cells share one editor for native deletion, paste and autofill.
class DesktopLoginCodeInput extends StatefulWidget {
  const DesktopLoginCodeInput({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  State<DesktopLoginCodeInput> createState() => _DesktopLoginCodeInputState();
}

class _DesktopLoginCodeInputState extends State<DesktopLoginCodeInput> {
  final _focus = FocusNode();
  static const _length = 6;
  static const _label = '输入电脑上的六位数字';

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final textStyle = theme.textTheme.titleLarge!.copyWith(
      color: AppTokens.textPrimary(dark: dark),
      fontWeight: FontWeight.w600,
    );
    final height = math.max(
        AuthTokens.controlHeight,
        MediaQuery.textScalerOf(context).scale(textStyle.fontSize!) +
            AppTokens.s5);
    final fill = AppTokens.surface(dark: dark);
    final border = AppTokens.textSecondary(dark: dark);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppTokens.s4),
        LayoutBuilder(builder: (context, constraints) {
          final width = math.min(AuthTokens.touchTarget,
              (constraints.maxWidth - AppTokens.s3 * (_length - 1)) / _length);
          return Semantics(
            label: _label,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: PinCodeTextField(
                appContext: context,
                length: _length,
                controller: widget.controller,
                focusNode: _focus,
                autoDisposeControllers: false,
                enabled: widget.enabled,
                autoUnfocus: false,
                autoDismissKeyboard: false,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                animationType: AnimationType.none,
                showCursor: false,
                enableActiveFill: true,
                enablePinAutofill: true,
                beforeTextPaste: (_) => true,
                textStyle: textStyle,
                cursorColor: AppTokens.accent,
                backgroundColor: theme.colorScheme.surface.withValues(alpha: 0),
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(AppTokens.rSm),
                  fieldWidth: width,
                  fieldHeight: height,
                  activeColor: border,
                  inactiveColor: border,
                  selectedColor: AppTokens.accent,
                  disabledColor: AppTokens.border(dark: dark),
                  activeFillColor: fill,
                  inactiveFillColor: fill,
                  selectedFillColor: fill,
                  errorBorderColor: theme.colorScheme.error,
                ),
                onChanged: (_) {},
              ),
            ),
          );
        }),
      ],
    );
  }
}
