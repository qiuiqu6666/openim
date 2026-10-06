import 'package:flutter/material.dart';

import '../../../widgets/auth/auth_copy.dart';
import '../../../widgets/auth/auth_reference.dart';
import '../../mine/settings/pages/legal_document_page.dart';
import '../rules/register_password_rules.dart';

/// Measurements and feedback colors from the reference registration form.
abstract final class RegistrationReferenceTokens {
  static const avatarRadius = 44.0;
  static const avatarIconSize = 30.0;
  static const profileGap = AuthReferenceTokens.fieldGap;
  static const profileAgreementGap = 20.0;
  static const stepGap = 8.0;
  static const ruleGap = 4.0;
  static const actionGap = AuthReferenceTokens.buttonGap;
  static const ruleAreaMinHeight = 20.0;
  static const feedbackFieldGap = AuthReferenceTokens.feedbackFieldGap;
  static const success = Color(0xFF059669);
  static const caption = AuthReferenceTokens.caption;
}

class RegistrationStepHeading extends StatelessWidget {
  const RegistrationStepHeading(
      {super.key, required this.label, required this.step});

  final String label;
  final int step;

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.only(bottom: RegistrationReferenceTokens.stepGap),
        child: Text(
          authText('$label · 第 $step/2 步', '$label · Step $step of 2'),
          key: ValueKey('registration-step-$step'),
          style: AuthReferenceTokens.caption,
        ),
      );
}

class RegisterPasswordChecklist extends StatelessWidget {
  const RegisterPasswordChecklist(
      {super.key, required this.password, this.showInvalid = false});
  final String password;
  final bool showInvalid;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: RegistrationReferenceTokens.ruleAreaMinHeight),
        child: Wrap(spacing: 10, runSpacing: 4, children: [
          _rule(authText('8 位以上', '8+ characters'),
              RegisterPasswordRules.hasMinimumLength(password)),
          _rule(authText('英文字母', 'Letters'),
              RegisterPasswordRules.hasLetter(password)),
          _rule(authText('数字', 'Numbers'),
              RegisterPasswordRules.hasDigit(password)),
        ]),
      );

  Widget _rule(String text, bool ok) {
    final color = ok
        ? RegistrationReferenceTokens.success
        : showInvalid
            ? AuthReferenceTokens.error
            : AuthReferenceTokens.ink400;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(
        ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        size: 13,
        color: color,
      ),
      const SizedBox(width: 3),
      Text(text,
          style: RegistrationReferenceTokens.caption
              .copyWith(color: color, height: 1.2)),
    ]);
  }
}

class RegisterAgreement extends StatelessWidget {
  const RegisterAgreement({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 13,
      height: 1.5,
      color: AuthReferenceTokens.ink400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(authText('注册代表同意', 'By registering, you agree to'),
                style: style),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      const LegalDocumentPage(kind: LegalDocumentKind.terms))),
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(authText('《用户协议》', '《User Agreement》'),
                    style: style.copyWith(
                      color: AuthReferenceTokens.link,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
