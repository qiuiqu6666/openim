import '../../widgets/auth/auth_agreement.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../routes/app_navigator.dart';
import '../../widgets/auth/auth_copy.dart';
import '../../widgets/auth/auth_reference.dart';
import '../../widgets/auth/auth_minimal_layout.dart';
import '../login/widgets/login_toolbar.dart';
import 'register_logic.dart';
import '../../widgets/auth/auth_identity_selector.dart';
import 'rules/registration_field.dart';
import 'widgets/register_reference_widgets.dart';

class RegisterPage extends StatelessWidget {
  RegisterPage({super.key});
  static const _fieldGap = RegistrationReferenceTokens.feedbackFieldGap;
  static const _countryWidth = kIsWeb ? 118.0 : 102.0;
  final logic = Get.find<RegisterLogic>();

  Future<void> _submit(BuildContext context) async {
    FocusScope.of(context).unfocus();
    await logic.next();
  }

  @override
  Widget build(BuildContext context) {
    return AuthMinimalLayout(
      onBack: () {
        if (!logic.submitting.value) AppNavigator.startBackLogin();
      },
      footer: const AuthEntryFooter(),
      child: AutofillGroup(
        child: Obx(() {
          final busy = logic.submitting.value || logic.accountCreated;
          final phone = !logic.emailMode.value;
          return Column(
            key: const ValueKey('register'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthIdentitySelector(
                  action: authText('注册', ' register'),
                  email: !phone,
                  onChanged: busy ? null : logic.selectEmail),
              AuthCompoundField(
                label: phone ? authText('手机号', 'Phone') : StrRes.email,
                controller: logic.phoneCtrl,
                focusNode: logic.phoneFocus,
                hint: phone
                    ? authText('请输入手机号', 'Enter phone number')
                    : StrRes.plsEnterEmail,
                keyboardType:
                    phone ? TextInputType.phone : TextInputType.emailAddress,
                autofillHints: [
                  phone
                      ? AutofillHints.telephoneNumberNational
                      : AutofillHints.email
                ],
                enabled: !busy,
                errorText: logic.errorFor(RegistrationField.account),
                reserveErrorSpace: true,
                onFocusChanged: (focused) {
                  if (!focused) logic.touchField(RegistrationField.account);
                },
                inputFormatters:
                    phone ? [FilteringTextInputFormatter.digitsOnly] : null,
                maxLength: phone ? 15 : null,
                leading: phone
                    ? AuthCountryCode(
                        code: logic.areaCode.value,
                        onTap: busy ? null : logic.openCountryCodePicker)
                    : null,
                leadingWidth: _countryWidth,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => logic.nicknameFocus.requestFocus(),
              ),
              const SizedBox(height: _fieldGap),
              AuthTextField(
                label: authText('昵称', 'Nickname'),
                controller: logic.nicknameCtrl,
                focusNode: logic.nicknameFocus,
                hint: authText('请输入昵称（至少2个字符）',
                    'Enter a nickname (at least 2 characters)'),
                keyboardType: TextInputType.text,
                autofillHints: const [AutofillHints.nickname],
                enabled: !busy,
                errorText: logic.errorFor(RegistrationField.nickname),
                reserveErrorSpace: true,
                onFocusChanged: (focused) {
                  if (!focused) logic.touchField(RegistrationField.nickname);
                },
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => logic.pwdFocus.requestFocus(),
              ),
              const SizedBox(height: _fieldGap),
              AuthTextField(
                label: authText('密码', 'Password'),
                controller: logic.pwdCtrl,
                focusNode: logic.pwdFocus,
                hint: authText('登录密码为8–24个字母及数字组合',
                    '8–24 characters with letters and numbers'),
                obscureText: logic.obscurePassword.value,
                keyboardType: TextInputType.visiblePassword,
                autofillHints: const [AutofillHints.newPassword],
                inputFormatters: [IMUtils.getPasswordFormatter()],
                enabled: !busy,
                errorText: logic.errorFor(RegistrationField.password),
                showErrorMessage: logic.pwdCtrl.text.isEmpty,
                onFocusChanged: (focused) {
                  if (!focused) logic.touchField(RegistrationField.password);
                },
                suffix:
                    _visibility(context, logic.obscurePassword, enabled: !busy),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => logic.pwdAgainFocus.requestFocus(),
              ),
              const SizedBox(height: RegistrationReferenceTokens.ruleGap),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: logic.pwdCtrl,
                builder: (_, value, __) => RegisterPasswordChecklist(
                    password: value.text,
                    showInvalid:
                        logic.errorFor(RegistrationField.password) != null),
              ),
              const SizedBox(height: _fieldGap),
              AuthTextField(
                label: authText('确认密码', 'Confirm password'),
                controller: logic.pwdAgainCtrl,
                focusNode: logic.pwdAgainFocus,
                hint: authText('请再次输入登录密码', 'Re-enter your login password'),
                obscureText: logic.obscureConfirmPassword.value,
                keyboardType: TextInputType.visiblePassword,
                autofillHints: const [AutofillHints.newPassword],
                inputFormatters: [IMUtils.getPasswordFormatter()],
                enabled: !busy,
                errorText: logic.errorFor(RegistrationField.confirmation),
                reserveErrorSpace: true,
                onFocusChanged: (focused) {
                  if (!focused) {
                    logic.touchField(RegistrationField.confirmation);
                  }
                },
                suffix: _visibility(context, logic.obscureConfirmPassword,
                    enabled: !busy),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => logic.codeFocus.requestFocus(),
              ),
              const SizedBox(height: _fieldGap),
              AuthCompoundField(
                controller: logic.verificationCodeCtrl,
                label: authText('验证码', 'Verification code'),
                focusNode: logic.codeFocus,
                hint: authText('请输入验证码', 'Enter verification code'),
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                enabled: !busy,
                errorText: logic.errorFor(RegistrationField.code),
                reserveErrorSpace: true,
                onFocusChanged: (focused) {
                  if (!focused) logic.touchField(RegistrationField.code);
                },
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                trailing: AuthCodeAction(
                    onSend: logic.requestVerificationCode, enabled: !busy),
                trailingWidth: 122,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(context),
              ),
              const SizedBox(height: _fieldGap),
              if (logic.needInvitationCodeRegister) ...[
                const SizedBox(height: _fieldGap),
                AuthTextField(
                  controller: logic.invitationCodeCtrl,
                  label: authText('邀请码', 'Invitation code'),
                  hint:
                      StrRes.plsEnterInvitationCode.replaceAll('%s', '').trim(),
                  enabled: !busy,
                  errorText: logic.errorFor(RegistrationField.invitation),
                  reserveErrorSpace: true,
                  onFocusChanged: (focused) {
                    if (!focused) {
                      logic.touchField(RegistrationField.invitation);
                    }
                  },
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(context),
                ),
              ],
              const SizedBox(height: RegistrationReferenceTokens.actionGap),
              AuthPrimaryButton(
                key: const ValueKey('register-submit'),
                text: logic.accountCreated
                    ? authText('继续完成注册', 'Continue registration')
                    : authText('注册', 'Register'),
                loadingText: authText('正在注册', 'Registering'),
                loading: logic.submitting.value,
                pill: true,
                onPressed: logic.enabled.value ? () => _submit(context) : null,
              ),
              const SizedBox(height: RegistrationReferenceTokens.actionGap),
              Center(child: AuthAgreement(accepted: logic.agreementAccepted.value, onChanged: busy ? null : logic.setAgreementAccepted)),
            ],
          );
        }),
      ),
    );
  }

  Widget _visibility(BuildContext context, RxBool obscured,
          {required bool enabled}) =>
      IconButton(
        tooltip: obscured.value
            ? authText('显示密码', 'Show password')
            : authText('隐藏密码', 'Hide password'),
        constraints: const BoxConstraints(
          minWidth: AuthReferenceTokens.tapTarget,
          minHeight: AuthReferenceTokens.tapTarget,
        ),
        padding: const EdgeInsets.all(12),
        visualDensity: VisualDensity.standard,
        onPressed: enabled ? () => obscured.toggle() : null,
        icon: Icon(
          obscured.value
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
          color: AuthReferenceTokens.color(context, AuthReferenceTokens.ink300),
        ),
      );
}
