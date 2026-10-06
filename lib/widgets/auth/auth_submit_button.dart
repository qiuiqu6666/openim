import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'auth_tokens.dart';

/// Applies the same theme to the existing shared button across auth steps.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.text,
    required this.enabled,
    required this.onTap,
    this.loading = false,
    this.gradient,
    this.trailingIcon,
  });
  final String text;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  final Gradient? gradient;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Button(
      text: text,
      enabled: enabled,
      loading: loading,
      gradient: gradient,
      trailingIcon: trailingIcon,
      onTap: onTap,
      height: AuthTokens.controlHeight,
      radius: AuthTokens.radius,
      enabledColor: colors.primary,
      disabledColor: colors.onSurface.withValues(alpha: .08),
      textStyle: gradient == null
          ? AuthTokens.action(context)
          : AuthTokens.action(context).copyWith(
              color: AppTokens.onAccent,
              fontWeight: FontWeight.w700,
              fontSize: AuthTokens.welcomeButtonSize),
      disabledTextStyle: gradient == null
          ? AuthTokens.action(context)
              .copyWith(color: colors.onSurface.withValues(alpha: .38))
          : AuthTokens.action(context).copyWith(
              color: AppTokens.onAccent.withValues(alpha: .85),
              fontWeight: FontWeight.w700,
              fontSize: AuthTokens.welcomeButtonSize),
    );
  }
}
