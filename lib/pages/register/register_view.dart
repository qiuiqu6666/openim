import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../routes/app_navigator.dart';
import '../../widgets/auth/auth_copy.dart';
import '../../widgets/auth/auth_reference.dart';
import '../login/widgets/login_toolbar.dart';
import 'register_logic.dart';
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
    final phone = logic.loginController.operateType != LoginType.email;
    return AuthEntryScaffold(
      greeting: authText('你好，', 'Hello,'),
      accent: authText('欢迎使用99Chat', 'Welcome to 99Chat'),
      tabs: [authText('登录', 'Login'), authText('注册', 'Register')],
      activeTab: 1,
      onTabSelected: (tab) {
        if (tab == 0 && !logic.submitting.value) {
          AppNavigator.startBackLogin();
        }
      },
      headerAction: const LoginToolbar(),
      footer: const AuthVersionFooter(),
      child: AutofillGroup(
        child: Obx(() {
          final busy = logic.submitting.value;
          return Column(
            key: const ValueKey('register'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RegistrationStepHeading(
                  label: authText('填写账号', 'Account details'), step: 1),
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
                onFieldSubmitted: (_) => logic.codeFocus.requestFocus(),
              ),
              const SizedBox(height: _fieldGap),
              AuthCompoundField(
                controller: logic.verificationCodeCtrl,
                label: authText('验证码', 'Verification code'),
                focusNode: logic.codeFocus,
                hint: phone
                    ? authText('6 位短信验证码', '6-digit SMS code')
                    : authText('6 位邮箱验证码', '6-digit email code'),
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
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => logic.pwdFocus.requestFocus(),
              ),
              const SizedBox(height: _fieldGap),
              AuthTextField(
                label: authText('密码', 'Password'),
                controller: logic.pwdCtrl,
                focusNode: logic.pwdFocus,
                hint: authText('设置登录密码', 'Create a password'),
                obscureText: logic.obscurePassword.value,
                keyboardType: TextInputType.visiblePassword,
                autofillHints: const [AutofillHints.newPassword],
                inputFormatters: [IMUtils.getPasswordFormatter()],
                enabled: !busy,
                errorText: logic.errorFor(RegistrationField.password),
                showErrorMessage: false,
                onFocusChanged: (focused) {
                  if (!focused) logic.touchField(RegistrationField.password);
                },
                suffix: _visibility(logic.obscurePassword, enabled: !busy),
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
                hint: authText('再次输入密码', 'Re-enter password'),
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
                suffix:
                    _visibility(logic.obscureConfirmPassword, enabled: !busy),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(context),
              ),
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
              const RegisterAgreement(),
              const SizedBox(height: RegistrationReferenceTokens.actionGap),
              AuthPrimaryButton(
                key: const ValueKey('register-submit'),
                text: authText('下一步', 'Next'),
                loadingText: authText('正在验证', 'Verifying'),
                loading: busy,
                pill: true,
                onPressed: logic.enabled.value ? () => _submit(context) : null,
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _visibility(RxBool obscured, {required bool enabled}) => IconButton(
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
          color: AuthReferenceTokens.ink300,
        ),
      );
}
