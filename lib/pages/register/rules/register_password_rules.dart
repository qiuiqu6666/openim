import '../../../widgets/auth/auth_copy.dart';

/// The registration policy displayed by the reference 99Chat form.
abstract final class RegisterPasswordRules {
  static bool hasMinimumLength(String value) => value.length >= 8;
  static bool hasLetter(String value) => RegExp(r'[A-Za-z]').hasMatch(value);
  static bool hasDigit(String value) => RegExp(r'\d').hasMatch(value);

  static bool valid(String value) =>
      hasMinimumLength(value) && hasLetter(value) && hasDigit(value);

  static String? validate(String? value) {
    if ((value ?? '').isEmpty) return authText('请输入密码', 'Enter password');
    return valid(value!)
        ? null
        : authText('密码不符合要求', 'Password does not meet the requirements');
  }
}
