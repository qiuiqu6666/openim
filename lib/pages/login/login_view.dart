import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../widgets/auth/auth_copy.dart';
import '../../widgets/auth/auth_reference.dart';
import 'login_logic.dart';
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
    return Obx(() => AuthEntryScaffold(
          greeting: authText('你好，', 'Hello,'),
          accent: authText('欢迎使用99Chat', 'Welcome to 99Chat'),
          tabs: [authText('登录', 'Login'), authText('注册', 'Register')],
          activeTab: 0,
          onTabSelected: logic.submitting.value
              ? null
              : (index) {
                  if (index == 1) {
                    logic.operateType = LoginType.phone;
                    logic.registerNow();
                  }
                },
          headerAction: const LoginToolbar(),
          footer: AuthVersionFooter(version: logic.displayVersion.value),
          child: AutofillGroup(
              child:
                  logic.isPasswordLogin.value ? _passwordForm() : _smsForm()),
        ));
  }

  Widget _passwordForm() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('login-password-form'),
          children: [
            AuthFieldLabel(authText('账号', 'Account')),
            AuthTextField(
                key: const ValueKey('login-account'),
                controller: logic.phoneCtrl,
                focusNode: logic.accountFocus,
                errorText: logic.accountError,
                reserveErrorSpace: true,
                onFocusChanged: logic.accountFocusChanged,
                enabled: !logic.submitting.value,
                hint: authText('请输入手机号或用户ID', 'Enter phone number or user ID'),
                autofillHints: const [AutofillHints.username],
                onFieldSubmitted: (_) => logic.pwdFocus?.requestFocus()),
            const SizedBox(height: AuthReferenceTokens.feedbackFieldGap),
            AuthFieldLabel(authText('密码', 'Password')),
            AuthTextField(
                key: const ValueKey('login-password'),
                controller: logic.pwdCtrl,
                focusNode: logic.pwdFocus,
                errorText: logic.passwordError,
                reserveErrorSpace: true,
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
                        color: AuthReferenceTokens.ink300))),
            const SizedBox(height: 8),
            _passwordOptions(),
            _submission(),
          ]);

  Widget _smsForm() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('login-sms-form'),
          children: [
            AuthFieldLabel(authText('手机号', 'Phone number')),
            AuthCompoundField(
                key: const ValueKey('login-account'),
                controller: logic.phoneCtrl,
                focusNode: logic.accountFocus,
                errorText: logic.accountError,
                reserveErrorSpace: true,
                onFocusChanged: logic.accountFocusChanged,
                enabled: !logic.submitting.value,
                hint: authText('请输入手机号', 'Enter phone number'),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 15,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                leadingWidth: 102,
                leading: AuthCountryCode(
                    code: logic.areaCode.value,
                    onTap: logic.submitting.value
                        ? null
                        : logic.openCountryCodePicker)),
            const SizedBox(height: AuthReferenceTokens.feedbackFieldGap),
            AuthCompoundField(
                key: const ValueKey('login-code'),
                controller: logic.verificationCodeCtrl,
                errorText: logic.codeError,
                reserveErrorSpace: true,
                onFocusChanged: logic.codeFocusChanged,
                enabled: !logic.submitting.value,
                hint: authText('6 位短信验证码', '6-digit SMS code'),
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
      text: authText('登录', 'Login'),
      loadingText: authText('登录中', 'Logging in'),
      pill: true,
      loading: logic.submitting.value,
      onPressed: logic.enabled.value ? _submit : null);

  Widget _passwordOptions() => SizedBox(
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
                                  color: AuthReferenceTokens.ink400))),
                    ]))),
            _action(authText('忘记密码', 'Forgot password'), logic.forgetPassword,
                key: const ValueKey('login-forgot-password')),
          ]));

  Widget _submission() => Column(children: [
        if (logic.formError != null) ...[
          const SizedBox(height: 8),
          AuthFormMessage(text: logic.formError),
        ],
        const SizedBox(height: AuthReferenceTokens.buttonGap),
        _button(),
        const SizedBox(height: 4),
        Center(
            child: _action(
                logic.isPasswordLogin.value
                    ? authText('验证码登录', 'Use SMS code')
                    : authText('密码登录', 'Use password'),
                logic.togglePasswordType,
                key: const ValueKey('login-mode-switch'))),
      ]);

  Widget _action(String text, VoidCallback onTap, {Key? key}) => Builder(
      builder: (context) => TextButton(
          key: key,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 48),
              foregroundColor: AuthReferenceTokens.link,
              textStyle: AuthReferenceTokens.label.copyWith(
                  fontWeight: FontWeight.w400,
                  fontFamily:
                      Theme.of(context).textTheme.bodyMedium?.fontFamily)),
          onPressed: logic.submitting.value ? null : onTap,
          child: Text(text, textAlign: TextAlign.center)));
}
