import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/auth/auth_copy.dart';
import '../../../widgets/auth/auth_input.dart';
import '../../../widgets/auth/auth_flow_footer.dart';
import '../../../widgets/auth/auth_submit_button.dart';
import '../../../widgets/auth/auth_tokens.dart';
import '../../../widgets/register_page_bg.dart';
import '../../../routes/app_navigator.dart';
import '../../login/widgets/login_toolbar.dart';
import 'verify_phone_logic.dart';

class VerifyPhonePage extends StatelessWidget {
  VerifyPhonePage({super.key});
  final logic = Get.find<VerifyPhoneLogic>();

  @override
  Widget build(BuildContext context) => RegisterBgView(
        centeredHeader: true,
        showWaves: true,
        toolbar: const LoginToolbar(),
        title: authText('验证你的账号', 'Verify your account'),
        subtitle:
            authText('输入发送至以下账号的验证码', 'Enter the code sent to this account.'),
        step: 2,
        totalSteps: 3,
        child: AutofillGroup(
          child: Obx(() => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(logic.account,
                      textAlign: TextAlign.center,
                      style: AuthTokens.body(context).copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: AuthTokens.welcomeFieldGap),
                  AuthInput(
                    leadingIcon: CupertinoIcons.number,
                    enabled: !logic.submitting.value,
                    label: StrRes.verificationCode,
                    hintText: StrRes.plsEnterVerificationCode,
                    controller: logic.codeEditCtrl,
                    keyBoardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6)
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (logic.enabled.value) {
                        logic.completed(logic.codeEditCtrl.text);
                      }
                    },
                  ),
                  const SizedBox(height: AppTokens.s3),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppTokens.s3,
                    children: [
                      Text(authText('没收到验证码？', 'Did not receive a code?'),
                          style: AuthTokens.body(context)),
                      VerifyCodedButton(
                        themed: true,
                        autoStart: true,
                        seconds: 300,
                        enabled: !logic.submitting.value,
                        onTapCallback: logic.requestVerificationCode,
                      ),
                    ],
                  ),
                  const SizedBox(height: AuthTokens.sectionGap),
                  AuthSubmitButton(
                    key: const ValueKey('verify-submit'),
                    text: StrRes.nextStep,
                    gradient: AuthTokens.welcomeGradient(context),
                    trailingIcon: Icons.arrow_forward_rounded,
                    enabled: logic.enabled.value,
                    loading: logic.submitting.value,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      logic.completed(logic.codeEditCtrl.text);
                    },
                  ),
                  const SizedBox(height: AuthTokens.sectionGap),
                  AuthFlowFooter(
                    prompt: authText('已有账号？', 'Already have an account?'),
                    action: authText('返回登录', 'Sign in'),
                    onTap: AppNavigator.startBackLogin,
                  ),
                ],
              )),
        ),
      );
}
