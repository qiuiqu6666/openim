import '../../../widgets/auth/auth_copy.dart';
import '../../../widgets/auth/auth_password_rules.dart';

/// The registration policy displayed by the reference 99Chat form.
abstract final class RegisterPasswordRules {
  static bool hasMinimumLength(String value) => value.length >= 8;
  static bool hasValidLength(String value) =>
      AuthPasswordRules.hasValidLength(value);
  static bool hasLetter(String value) => AuthPasswordRules.hasLetter(value);
  static bool hasDigit(String value) => AuthPasswordRules.hasDigit(value);
  static bool valid(String value) => AuthPasswordRules.valid(value);

  static String? validate(String? value) {
    if ((value ?? '').isEmpty) return authText('请输入密码', 'Enter password');
    return valid(value!)
        ? null
        : authText('密码不符合要求', 'Password does not meet the requirements');
  }
}
