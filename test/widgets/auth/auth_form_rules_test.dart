import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/auth/auth_form_rules.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  setUp(() {
    Get.addTranslations(TranslationService().keys);
  });

  tearDown(Get.reset);

  for (final english in [false, true]) {
    test(
        'auth validation follows the selected ${english ? 'English' : 'Chinese'} locale',
        () {
      Get.locale =
          english ? const Locale('en', 'US') : const Locale('zh', 'CN');
      expect(AuthFormRules.phone('  ', '+86'),
          english ? 'Please enter your phone number' : '请输入您的手机号');
      expect(AuthFormRules.email('  '),
          english ? 'Please enter your email' : '请输入您的邮箱');
      expect(AuthFormRules.account('  '),
          english ? 'Please enter your account' : '请输入您的账号');
      expect(AuthFormRules.loginPassword('  '),
          english ? 'Please enter your password' : '请输入您的密码');
      expect(AuthFormRules.password('  '),
          english ? 'Please enter your password' : '请输入您的密码');
      expect(AuthFormRules.confirmPassword('', 'password1'),
          english ? 'Please enter your password again' : '请再次输入密码');
      expect(AuthFormRules.verificationCode('  '),
          english ? 'Please enter your verification code' : '请输入您的验证码');
      expect(
          AuthFormRules.verificationCode('12ab', sixDigits: true),
          english
              ? 'Please enter the 6-digit verification code'
              : '请输入6位数字验证码');
      expect(AuthFormRules.invitationCode('  ', isRequired: true),
          english ? 'Please enter your invitation code' : '请输入您的邀请码');
      expect(AuthFormRules.phone('wrong', '+86'),
          isNot(AuthFormRules.phone('', '+86')));
      expect(AuthFormRules.email('wrong'), isNot(AuthFormRules.email('')));
    });
  }

  test(
      'validation accepts existing credentials and server-owned invite formats',
      () {
    Get.locale = const Locale('zh', 'CN');
    expect(AuthFormRules.phone(' 13800138000 ', '+86'), isNull);
    expect(AuthFormRules.phone('not-a-number', '+1'), isNotNull);
    expect(AuthFormRules.email(' user@example.com '), isNull);
    expect(AuthFormRules.loginPassword('short'), isNull);
    expect(AuthFormRules.password('short'), isNotNull);
    expect(AuthFormRules.password('password1'), isNull);
    expect(AuthFormRules.invitationCode(''), isNull);
    expect(
        AuthFormRules.invitationCode('server-owned-format', isRequired: true),
        isNull);
    expect(AuthFormRules.verificationCode(' 123456 ', sixDigits: true), isNull);
  });
}
