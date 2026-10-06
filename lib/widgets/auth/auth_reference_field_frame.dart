import 'package:flutter/material.dart';

import 'auth_reference_feedback.dart';
import 'auth_reference_tokens.dart';

/// Shared focus/error chrome for single and compound authentication fields.
class AuthFieldFrame extends StatelessWidget {
  const AuthFieldFrame({
    super.key,
    required this.child,
    required this.focused,
    required this.enabled,
    this.errorText,
    this.reserveErrorSpace = false,
    this.showErrorMessage = true,
    this.showBorder = true,
    this.inputFontSize = AuthReferenceTokens.inputFontSize,
  });

  final Widget child;
  final bool focused;
  final bool enabled;
  final String? errorText;
  final bool reserveErrorSpace;
  final bool showErrorMessage;
  final bool showBorder;
  final double inputFontSize;

  @override
  Widget build(BuildContext context) {
    final invalid = errorText?.trim().isNotEmpty ?? false;
    final border = invalid
        ? AuthReferenceTokens.error
        : focused && enabled
            ? AuthReferenceTokens.brand500
            : AuthReferenceTokens.fieldBorder;
    final inputHeight =
        MediaQuery.textScalerOf(context).scale(inputFontSize) * 1.2;
    final height = (inputHeight + 28)
        .clamp(AuthReferenceTokens.fieldHeight, double.infinity);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        height: height,
        decoration: BoxDecoration(
          color: AuthReferenceTokens.fieldFill,
          borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg),
        ),
        foregroundDecoration: !showBorder
            ? null
            : BoxDecoration(
                border: Border.all(color: border, width: 1.5),
                borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg),
              ),
        child: child,
      ),
      if (showErrorMessage)
        AuthFieldMessage(text: errorText, reserveSpace: reserveErrorSpace),
    ]);
  }
}
