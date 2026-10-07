import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../widgets/auth/auth_copy.dart';
import '../../../../widgets/auth/auth_reference.dart';
import '../../widgets/register_reference_widgets.dart';

/// Completes credentials when an older verification route has no password.
class LegacyRegistrationPasswordFields extends StatefulWidget {
  const LegacyRegistrationPasswordFields({
    super.key,
    required this.passwordController,
    required this.confirmationController,
    required this.enabled,
    this.passwordError,
    this.confirmationError,
    this.onPasswordFocusChanged,
    this.onConfirmationFocusChanged,
    this.onSubmitted,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmationController;
  final bool enabled;
  final String? passwordError;
  final String? confirmationError;
  final ValueChanged<bool>? onPasswordFocusChanged;
  final ValueChanged<bool>? onConfirmationFocusChanged;
  final VoidCallback? onSubmitted;

  @override
  State<LegacyRegistrationPasswordFields> createState() =>
      _LegacyRegistrationPasswordFieldsState();
}

class _LegacyRegistrationPasswordFieldsState
    extends State<LegacyRegistrationPasswordFields> {
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthTextField(
            label: authText('密码', 'Password'),
            key: const ValueKey('legacy-registration-password'),
            controller: widget.passwordController,
            hint: authText('设置登录密码', 'Create a password'),
            obscureText: _obscurePassword,
            keyboardType: TextInputType.visiblePassword,
            autofillHints: const [AutofillHints.newPassword],
            inputFormatters: [IMUtils.getPasswordFormatter()],
            enabled: widget.enabled,
            errorText: widget.passwordError,
            showErrorMessage: false,
            onFocusChanged: widget.onPasswordFocusChanged,
            suffix: _visibility(_obscurePassword, () {
              setState(() => _obscurePassword = !_obscurePassword);
            }),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: RegistrationReferenceTokens.ruleGap),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.passwordController,
            builder: (_, value, __) => RegisterPasswordChecklist(
                password: value.text,
                showInvalid: widget.passwordError != null),
          ),
          const SizedBox(height: RegistrationReferenceTokens.feedbackFieldGap),
          AuthTextField(
            label: authText('确认密码', 'Confirm password'),
            key: const ValueKey('legacy-registration-confirmation'),
            controller: widget.confirmationController,
            hint: authText('再次输入密码', 'Re-enter password'),
            obscureText: _obscureConfirmation,
            keyboardType: TextInputType.visiblePassword,
            autofillHints: const [AutofillHints.newPassword],
            inputFormatters: [IMUtils.getPasswordFormatter()],
            enabled: widget.enabled,
            errorText: widget.confirmationError,
            reserveErrorSpace: true,
            onFocusChanged: widget.onConfirmationFocusChanged,
            suffix: _visibility(_obscureConfirmation, () {
              setState(() => _obscureConfirmation = !_obscureConfirmation);
            }),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          ),
        ],
      );

  Widget _visibility(bool obscured, VoidCallback toggle) => IconButton(
        tooltip: obscured
            ? authText('显示密码', 'Show password')
            : authText('隐藏密码', 'Hide password'),
        constraints: const BoxConstraints(
          minWidth: AuthReferenceTokens.tapTarget,
          minHeight: AuthReferenceTokens.tapTarget,
        ),
        padding: const EdgeInsets.all(12),
        visualDensity: VisualDensity.standard,
        onPressed: widget.enabled ? toggle : null,
        icon: Icon(
          obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: AuthReferenceTokens.ink300,
        ),
      );
}
