import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../routes/app_navigator.dart';
import '../../../widgets/auth/auth_copy.dart';
import '../../../widgets/auth/auth_reference.dart';
import '../../login/widgets/login_toolbar.dart';
import '../widgets/register_reference_widgets.dart';
import '../rules/registration_field.dart';
import 'set_password_logic.dart';
import 'widgets/legacy_registration_password_fields.dart';
import 'widgets/registration_avatar_picker.dart';

/// The second registration step retains the existing route binding.
class SetPasswordPage extends StatelessWidget {
  SetPasswordPage({super.key});
  final logic = Get.find<SetPasswordLogic>();

  @override
  Widget build(BuildContext context) => Obx(() {
        final busy = logic.submitting.value;
        final picking = logic.pickingAvatar.value;
        final enabled = !busy && !picking;
        final editable = enabled && !logic.accountCreated.value;
        return PopScope(
          canPop: editable,
          child: AuthEntryScaffold(
            greeting: authText('你好，', 'Hello,'),
            accent: authText('欢迎使用99Chat', 'Welcome to 99Chat'),
            tabs: [authText('登录', 'Login'), authText('注册', 'Register')],
            activeTab: 1,
            onTabSelected: (tab) {
              if (tab == 0 && enabled) AppNavigator.startBackLogin();
            },
            headerAction: const LoginToolbar(),
            footer: const AuthVersionFooter(),
            child: AutofillGroup(
              child: Column(
                key: const ValueKey('register-profile-step'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RegistrationStepHeading(
                      label: authText('设置资料', 'Profile details'), step: 2),
                  RegistrationAvatarPicker(
                    bytes: logic.avatar.value?.bytes,
                    enabled: enabled,
                    picking: picking,
                    onPick: logic.pickAvatar,
                  ),
                  const SizedBox(
                      height: RegistrationReferenceTokens.profileGap),
                  AuthFieldLabel(authText('昵称', 'Nickname')),
                  AuthTextField(
                    controller: logic.nicknameCtrl,
                    focusNode: logic.nicknameFocus,
                    hint: authText('请输入昵称', 'Enter nickname'),
                    autofillHints: const [AutofillHints.nickname],
                    enabled: editable,
                    errorText: logic.errorFor(RegistrationField.nickname),
                    reserveErrorSpace: true,
                    onFocusChanged: (focused) {
                      if (!focused) {
                        logic.touchField(RegistrationField.nickname);
                      }
                    },
                    textInputAction: logic.credentialPasswordProvided
                        ? TextInputAction.done
                        : TextInputAction.next,
                    onFieldSubmitted: (_) {
                      if (!logic.credentialPasswordProvided) return;
                      FocusScope.of(context).unfocus();
                      if (enabled) logic.nextStep();
                    },
                  ),
                  const SizedBox(
                      height: RegistrationReferenceTokens.profileAgreementGap),
                  if (!logic.credentialPasswordProvided) ...[
                    LegacyRegistrationPasswordFields(
                      passwordController: logic.pwdCtrl,
                      confirmationController: logic.pwdAgainCtrl,
                      enabled: editable,
                      passwordError: logic.errorFor(RegistrationField.password),
                      confirmationError:
                          logic.errorFor(RegistrationField.confirmation),
                      onPasswordFocusChanged: (focused) {
                        if (!focused) {
                          logic.touchField(RegistrationField.password);
                        }
                      },
                      onConfirmationFocusChanged: (focused) {
                        if (!focused) {
                          logic.touchField(RegistrationField.confirmation);
                        }
                      },
                      onSubmitted: () {
                        FocusScope.of(context).unfocus();
                        if (enabled) logic.nextStep();
                      },
                    ),
                    const SizedBox(
                        height:
                            RegistrationReferenceTokens.profileAgreementGap),
                  ],
                  const RegisterAgreement(),
                  const SizedBox(height: RegistrationReferenceTokens.actionGap),
                  AuthPrimaryButton(
                    key: const ValueKey('signup-submit'),
                    text: logic.submitLabel,
                    loadingText: authText('正在处理', 'Processing'),
                    loading: busy,
                    pill: true,
                    onPressed:
                        logic.enabled.value && enabled ? logic.nextStep : null,
                  ),
                  Center(
                    child: TextButton(
                      key: const ValueKey('register-profile-back'),
                      onPressed: editable ? () => Get.back() : null,
                      child: Text(authText('上一步', 'Back')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      });
}
