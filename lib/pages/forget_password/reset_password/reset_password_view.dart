import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:get/get.dart';
import 'package:openim/pages/login/widgets/login_toolbar.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import '../../../widgets/auth/auth_copy.dart';
import '../../../widgets/auth/auth_flow_footer.dart';
import '../../../widgets/auth/auth_form_rules.dart';
import '../../../widgets/auth/auth_input.dart';
import '../../../widgets/auth/auth_submit_button.dart';
import '../../../widgets/auth/auth_tokens.dart';
import '../../../widgets/register_page_bg.dart';
import 'reset_password_logic.dart';

class ResetPasswordPage extends StatelessWidget {
  ResetPasswordPage({super.key});
  final logic = Get.find<ResetPasswordLogic>();
  final _formKey = GlobalKey<FormState>();

  Future<void> _submit(BuildContext context) async {
    FocusScope.of(context).unfocus();
    if (logic.enabled.value && _formKey.currentState!.validate()) {
      await logic.confirmTheChanges();
    }
  }

  @override
  Widget build(BuildContext context) => RegisterBgView(
        centeredHeader: true,
        showWaves: true,
        toolbar: const LoginToolbar(),
        title: authText('设置新密码', 'Set a new password'),
        subtitle: authText('设置完成后，使用新密码重新登录',
            'Use your new password to sign in after the reset.'),
        step: 2,
        totalSteps: 2,
        child: AutofillGroup(
          child: Form(
              key: _formKey,
              child: Obx(() => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthInput(
                            type: InputBoxType.password,
                            enabled: !logic.submitting.value,
                            label: authText('新密码', 'New password'),
                            hintText:
                                authText('请输入新密码', 'Enter your new password'),
                            leadingIcon: CupertinoIcons.lock,
                            controller: logic.pwdCtrl,
                            formatHintText: StrRes.loginPwdFormat,
                            autofillHints: const [AutofillHints.newPassword],
                            validator: AuthFormRules.password,
                            autovalidateMode: AutovalidateMode.onUnfocus,
                            inputFormatters: [IMUtils.getPasswordFormatter()]),
                        const SizedBox(height: AuthTokens.welcomeFieldGap),
                        AuthInput(
                            type: InputBoxType.password,
                            enabled: !logic.submitting.value,
                            label: StrRes.confirmPassword,
                            hintText: StrRes.plsConfirmPasswordAgain,
                            leadingIcon: CupertinoIcons.lock,
                            controller: logic.pwdAgainCtrl,
                            autofillHints: const [AutofillHints.newPassword],
                            validator: (value) => AuthFormRules.confirmPassword(
                                value, logic.pwdCtrl.text),
                            autovalidateMode: AutovalidateMode.onUnfocus,
                            inputFormatters: [IMUtils.getPasswordFormatter()],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(context)),
                        const SizedBox(height: AuthTokens.sectionGap),
                        AuthSubmitButton(
                            key: const ValueKey('reset-submit'),
                            text: StrRes.confirmTheChanges,
                            enabled: logic.enabled.value,
                            loading: logic.submitting.value,
                            gradient: AuthTokens.welcomeGradient(context),
                            trailingIcon: Icons.arrow_forward_rounded,
                            onTap: () => _submit(context)),
                        const SizedBox(height: AuthTokens.sectionGap),
                        AuthFlowFooter(
                          prompt: authText('想起密码了？', 'Remember your password?'),
                          action: authText('返回登录', 'Back to sign in'),
                          onTap: AppNavigator.startBackLogin,
                        ),
                      ]))),
        ),
      );
}
