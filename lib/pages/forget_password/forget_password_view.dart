import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:openim/pages/login/widgets/login_toolbar.dart';

import '../../widgets/auth/auth_copy.dart';
import '../../widgets/auth/auth_reference.dart';
import '../../widgets/auth/auth_minimal_layout.dart';
import 'forget_password_logic.dart';
import '../../widgets/auth/auth_identity_selector.dart';
import 'form/recovery_form_feedback.dart';

class ForgetPasswordPage extends StatefulWidget {
  const ForgetPasswordPage({super.key});

  @override
  State<ForgetPasswordPage> createState() => _ForgetPasswordPageState();
}

class _ForgetPasswordPageState extends State<ForgetPasswordPage> {
  final logic = Get.find<ForgetPasswordLogic>();
  bool _obscure = true;
  bool _confirmObscure = true;

  Future<void> _submit(BuildContext context) async {
    FocusScope.of(context).unfocus();
    await logic.nextStep();
  }

  Widget _passwordToggle({required bool confirm}) {
    final obscure = confirm ? _confirmObscure : _obscure;
    final label = obscure
        ? authText('显示密码', 'Show password')
        : authText('隐藏密码', 'Hide password');
    return IconButton(
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: const EdgeInsets.all(12),
      visualDensity: VisualDensity.standard,
      onPressed: logic.submitting.value
          ? null
          : () => setState(() {
                if (confirm) {
                  _confirmObscure = !_confirmObscure;
                } else {
                  _obscure = !_obscure;
                }
              }),
      icon: Icon(
        obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: AuthReferenceTokens.color(context, AuthReferenceTokens.ink300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AuthMinimalLayout(
        onBack: () => Get.back(),
        footer: const AuthEntryFooter(),
        child: AutofillGroup(
          child: Obx(() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AuthIdentitySelector(
                      action: authText('找回', ' recovery'),
                      email: logic.emailMode.value,
                      onChanged:
                          logic.submitting.value ? null : logic.selectEmail),
                  AuthCompoundField(
                    label: logic.emailMode.value
                        ? authText('邮箱', 'Email')
                        : authText('手机号', 'Phone'),
                    controller: logic.phoneCtrl,
                    hint: logic.emailMode.value
                        ? authText('请输入邮箱', 'Enter email')
                        : authText('请输入手机号', 'Enter phone number'),
                    enabled: !logic.submitting.value,
                    keyboardType: logic.emailMode.value
                        ? TextInputType.emailAddress
                        : TextInputType.phone,
                    inputFormatters: logic.emailMode.value
                        ? null
                        : [FilteringTextInputFormatter.digitsOnly],
                    maxLength: logic.emailMode.value ? 254 : 15,
                    errorText: logic.fieldError(RecoveryField.phone),
                    reserveErrorSpace: true,
                    onFocusChanged: (focused) =>
                        logic.onFocusChanged(RecoveryField.phone, focused),
                    autofillHints: [
                      logic.emailMode.value
                          ? AutofillHints.email
                          : AutofillHints.telephoneNumberNational
                    ],
                    leading: logic.emailMode.value
                        ? null
                        : AuthCountryCode(
                            code: logic.areaCode.value,
                            onTap: logic.submitting.value
                                ? null
                                : logic.openCountryCodePicker,
                          ),
                    leadingWidth: 102,
                  ),
                  const SizedBox(height: AuthReferenceTokens.feedbackFieldGap),
                  AuthCompoundField(
                    controller: logic.verificationCodeCtrl,
                    label: authText('验证码', 'Verification code'),
                    hint: logic.emailMode.value
                        ? authText('6 位邮箱验证码', '6-digit email code')
                        : authText('6 位短信验证码', '6-digit SMS code'),
                    enabled: !logic.submitting.value,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    errorText: logic.fieldError(RecoveryField.code),
                    reserveErrorSpace: true,
                    onFocusChanged: (focused) =>
                        logic.onFocusChanged(RecoveryField.code, focused),
                    autofillHints: const [AutofillHints.oneTimeCode],
                    trailing: AuthCodeAction(
                      onSend: logic.getVerificationCode,
                      enabled: !logic.submitting.value,
                    ),
                    trailingWidth: 122,
                  ),
                  const SizedBox(height: AuthReferenceTokens.feedbackFieldGap),
                  AuthTextField(
                    label: authText('新密码', 'New password'),
                    controller: logic.pwdCtrl,
                    hint: authText('登录密码为8–24个字母及数字组合',
                        'Use 8–24 characters with both letters and numbers only'),
                    errorText: logic.fieldError(RecoveryField.password),
                    reserveErrorSpace: true,
                    onFocusChanged: (focused) =>
                        logic.onFocusChanged(RecoveryField.password, focused),
                    enabled: !logic.submitting.value,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    suffix: _passwordToggle(confirm: false),
                  ),
                  const SizedBox(height: AuthReferenceTokens.feedbackFieldGap),
                  AuthTextField(
                    label: authText('确认新密码', 'Confirm new password'),
                    controller: logic.pwdAgainCtrl,
                    hint: authText('请再次输入登录密码', 'Re-enter your login password'),
                    errorText: logic.fieldError(RecoveryField.confirmation),
                    reserveErrorSpace: true,
                    onFocusChanged: (focused) => logic.onFocusChanged(
                        RecoveryField.confirmation, focused),
                    enabled: !logic.submitting.value,
                    obscureText: _confirmObscure,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(context),
                    suffix: _passwordToggle(confirm: true),
                  ),
                  const SizedBox(height: AuthReferenceTokens.buttonGap),
                  AuthFormMessage(text: logic.formError),
                  if (logic.formError != null)
                    const SizedBox(height: AuthReferenceTokens.fieldGap),
                  AuthPrimaryButton(
                    key: const ValueKey('recovery-submit'),
                    compact: true,
                    text: authText('重置密码', 'Reset Password'),
                    loading: logic.submitting.value,
                    pill: true,
                    onPressed:
                        logic.enabled.value ? () => _submit(context) : null,
                  ),
                ],
              )),
        ),
      );
}
