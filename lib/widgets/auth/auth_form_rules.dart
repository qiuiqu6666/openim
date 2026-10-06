import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'auth_copy.dart';

abstract final class AuthFormRules {
  static String? phone(String? value, String areaCode) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return StrRes.plsEnterPhoneNumber;
    return RegExp(r'^\d+$').hasMatch(phone) && IMUtils.isMobile(areaCode, phone)
        ? null
        : StrRes.plsEnterRightPhone;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return StrRes.plsEnterEmail;
    return email.isEmail ? null : StrRes.plsEnterRightEmail;
  }

  static String? account(String? value) =>
      (value?.trim() ?? '').isEmpty ? StrRes.plsEnterAccount : null;

  static String? loginPassword(String? value) =>
      (value?.trim() ?? '').isEmpty ? StrRes.plsEnterPassword : null;

  static String? password(String? value) =>
      loginPassword(value) ??
      (IMUtils.isValidPassword(value ?? '')
          ? null
          : StrRes.wrongPasswordFormat);

  static String? confirmPassword(String? value, String password) {
    if ((value?.trim() ?? '').isEmpty) {
      return authText('请再次输入密码', 'Please enter your password again');
    }
    return value == password ? null : StrRes.twicePwdNoSame;
  }

  static String? verificationCode(String? value, {bool sixDigits = false}) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return StrRes.plsEnterVerificationCode;
    if (sixDigits && !RegExp(r'^\d{6}$').hasMatch(code)) {
      return authText(
          '请输入6位数字验证码', 'Please enter the 6-digit verification code');
    }
    return null;
  }

  static String? invitationCode(String? value, {bool isRequired = false}) {
    if (isRequired && (value?.trim() ?? '').isEmpty) {
      return StrRes.plsEnterInvitationCode.replaceAll('%s', '').trim();
    }
    // The backend owns invitation validity; no local format is configured.
    return null;
  }
}
