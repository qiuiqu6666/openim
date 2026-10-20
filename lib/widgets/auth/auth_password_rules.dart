/// Shared policy for newly created login passwords.
abstract final class AuthPasswordRules {
  static bool hasValidLength(String value) =>
      value.length >= 8 && value.length <= 24;
  static bool hasLetter(String value) => RegExp(r'[A-Za-z]').hasMatch(value);
  static bool hasDigit(String value) => RegExp(r'[0-9]').hasMatch(value);
  static bool valid(String value) =>
      hasValidLength(value) &&
      hasLetter(value) &&
      hasDigit(value) &&
      RegExp(r'^[A-Za-z0-9]+$').hasMatch(value);
}
