import '../../widgets/auth/auth_agreement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../widgets/auth/auth_copy.dart';
import '../../widgets/auth/auth_reference.dart';
import '../../widgets/auth/auth_minimal_layout.dart';
import 'login_logic.dart';
import '../../widgets/auth/auth_identity_selector.dart';
import 'widgets/login_toolbar.dart';

class LoginPage extends StatelessWidget {
  LoginPage({super.key});
  final logic = Get.find<LoginLogic>();

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    logic.login();
  }

  @override
  Widget build(BuildContext context) {
    // Re-render retained local/server failures when the app locale changes.
    Localizations.localeOf(context);
    return Obx(() => AuthMinimalLayout(
          header: const LoginToolbar(onHero: false, showSupport: false),
          footer: Column(children: [
            AuthAgreement(
              accepted: logic.agreementAccepted.value,
              onChanged: logic.submitting.value ? null : logic.setAgreementAccepted,
            ),
            AuthEntryFooter(version: logic.displayVersion.value),
          ]),
          child: AutofillGroup(
              child: Column(children: [
            AuthIdentitySelector(
                showAccount: true,
                accountLabel: authText('账号登陆', 'Account login'),
                email: logic.loginType.value == LoginType.email,
                account: logic.loginType.value == LoginType.account,
                onAccountSelected: logic.submitting.value
                    ? null
                    : () => logic.selectLoginType(LoginType.account),
                action: authText('登录', ' login'),
                onChanged: logic.submitting.value
                    ? null
                    : (email) => logic.selectLoginType(
                        email ? LoginType.email : LoginType.phone)),
            logic.isPasswordLogin.value ? _passwordForm(context) : _smsForm(),
          ])),
        ));
  }

  Widget _passwordForm(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('login-password-form'),
          children: [
            AuthCompoundField(
                leadingWidth: 84,
                leading: logic.loginType.value == LoginType.phone
                    ? AuthCountryCode(
                        code: logic.areaCode.value,
                        onTap: logic.submitting.value
                            ? null
                            : logic.openCountryCodePicker)
                    : null,
                label: authText('账号', 'Account'),
                key: const ValueKey('login-account'),
                controller: logic.phoneCtrl,
                focusNode: logic.accountFocus,
                errorText: logic.accountError,
                reserveErrorSpace: true,
                onFocusChanged: logic.accountFocusChanged,
                enabled: !logic.submitting.value,
                hint: switch (logic.loginType.value) {
                  LoginType.phone => authText('手机号码', 'Phone number'),
                  LoginType.email => authText('邮箱地址', 'Email address'),
                  LoginType.account => authText('请输入账号', 'Enter account'),
                },
                keyboardType: switch (logic.loginType.value) {
                  LoginType.phone => TextInputType.phone,
                  LoginType.email => TextInputType.emailAddress,
                  LoginType.account => TextInputType.text,
                },
                inputFormatters: logic.loginType.value == LoginType.phone
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                autofillHints: const [AutofillHints.username],
                onFieldSubmitted: (_) => logic.pwdFocus?.requestFocus()),
            const SizedBox(height: AuthReferenceTokens.feedbackFieldGap),
            AuthTextField(
                label: authText('密码', 'Password'),
                key: const ValueKey('login-password'),
                controller: logic.pwdCtrl,
                focusNode: logic.pwdFocus,
                errorText: logic.passwordError,
                reserveErrorSpace: false,
                onFocusChanged: logic.passwordFocusChanged,
                enabled: !logic.submitting.value,
                hint: authText('请输入密码', 'Enter password'),
                obscureText: logic.obscureText.value,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                showClearButton: true,
                suffix: IconButton(
                    tooltip: logic.obscureText.value
                        ? authText('显示密码', 'Show password')
                        : authText('隐藏密码', 'Hide password'),
                    onPressed: logic.submitting.value
                        ? null
                        : () => logic.obscureText.toggle(),
                    icon: Icon(
                        logic.obscureText.value
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: AuthReferenceTokens.color(
                            context, AuthReferenceTokens.ink300)))),
            const SizedBox(height: AuthReferenceTokens.passwordOptionsGap),
            _passwordOptions(context),
            _submission(),
          ]);

  Widget _smsForm() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('login-sms-form'),
          children: [
            AuthCompoundField(
                label: logic.loginType.value == LoginType.email
                    ? authText('邮箱', 'Email')
                    : authText('手机号', 'Phone number'),
                key: const ValueKey('login-account'),
                controller: logic.phoneCtrl,
                focusNode: logic.accountFocus,
                errorText: logic.accountError,
                reserveErrorSpace: true,
                onFocusChanged: logic.accountFocusChanged,
                enabled: !logic.submitting.value,
                hint: logic.loginType.value == LoginType.email
                    ? authText('请输入邮箱', 'Enter email')
                    : authText('请输入手机号', 'Enter phone number'),
                keyboardType: logic.loginType.value == LoginType.email
                    ? TextInputType.emailAddress
                    : TextInputType.phone,
                inputFormatters: logic.loginType.value == LoginType.email
                    ? null
                    : [FilteringTextInputFormatter.digitsOnly],
                maxLength: logic.loginType.value == LoginType.email ? 254 : 15,
                autofillHints: [
                  logic.loginType.value == LoginType.email
                      ? AutofillHints.email
                      : AutofillHints.telephoneNumberNational
                ],
                leadingWidth: 102,
                leading: logic.loginType.value == LoginType.email
                    ? null
                    : AuthCountryCode(
                        code: logic.areaCode.value,
                        onTap: logic.submitting.value
                            ? null
                            : logic.openCountryCodePicker)),
            const SizedBox(height: AuthReferenceTokens.feedbackFieldGap),
            AuthCompoundField(
                key: const ValueKey('login-code'),
                label: authText('验证码', 'Verification code'),
                controller: logic.verificationCodeCtrl,
                errorText: logic.codeError,
                reserveErrorSpace: true,
                onFocusChanged: logic.codeFocusChanged,
                enabled: !logic.submitting.value,
                hint: logic.loginType.value == LoginType.email
                    ? authText('6 位邮箱验证码', '6-digit email code')
                    : authText('6 位短信验证码', '6-digit SMS code'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                trailingWidth: 122,
                trailing: AuthCodeAction(
                    onSend: logic.getVerificationCode,
                    enabled: !logic.submitting.value)),
            _submission(),
          ]);

  Widget _button() => AuthPrimaryButton(
      key: const ValueKey('login-submit'),
      compact: true,
      textStyle: AuthReferenceTokens.loginButton,
      text: authText('登录', 'Login'),
      loadingText: authText('登录中', 'Logging in'),
      pill: true,
      loading: logic.submitting.value,
      onPressed: logic.enabled.value ? _submit : null);

  Widget _passwordOptions(BuildContext context) => SizedBox(
      width: double.infinity,
      child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            InkWell(
                key: const ValueKey('login-remember-password'),
                onTap: logic.submitting.value
                    ? null
                    : () => logic
                        .toggleRememberPassword(!logic.rememberPassword.value),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                              value: logic.rememberPassword.value,
                              onChanged: logic.submitting.value
                                  ? null
                                  : (value) => logic
                                      .toggleRememberPassword(value ?? false),
                              activeColor: AuthReferenceTokens.brand500,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact)),
                      const SizedBox(width: 8),
                      Flexible(
                          child: Text(authText('记住密码', 'Remember password'),
                              style: AuthReferenceTokens.label.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: AuthReferenceTokens.color(
                                      context, AuthReferenceTokens.ink400)))),
                    ]))),
            _action(authText('忘记密码', 'Forgot password'), logic.forgetPassword,
                key: const ValueKey('login-forgot-password')),
          ]));

  Widget _submission() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            height: logic.isPasswordLogin.value
                ? AuthReferenceTokens.passwordSubmitGap
                : AuthReferenceTokens.buttonGap),
        _button(),
        const SizedBox(height: 4),
        Wrap(
            alignment: logic.loginType.value == LoginType.account
                ? WrapAlignment.end
                : WrapAlignment.spaceBetween,
            spacing: 24,
            children: [
              if (logic.loginType.value != LoginType.account)
                _action(
                    logic.isPasswordLogin.value
                        ? authText('验证码登录', 'Use verification code')
                        : authText('密码登录', 'Use password'),
                    logic.togglePasswordType,
                    key: const ValueKey('login-mode-switch')),
              _action(
                  authText('还没账户？去注册', 'Create an account'), logic.registerNow,
                  key: const ValueKey('login-register')),
            ]),
      ]);

  Widget _action(String text, VoidCallback onTap, {Key? key}) => Builder(
      builder: (context) => TextButton(
          key: key,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 48),
              foregroundColor:
                  AuthReferenceTokens.color(context, AuthReferenceTokens.link),
              textStyle: AuthReferenceTokens.label.copyWith(
                  fontWeight: FontWeight.w400,
                  fontFamily:
                      Theme.of(context).textTheme.bodyMedium?.fontFamily)),
          onPressed: logic.submitting.value ? null : onTap,
          child: Text(text, textAlign: TextAlign.center)));
}
