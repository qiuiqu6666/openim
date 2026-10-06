import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/src/res/strings.dart';
import 'package:openim_common/src/utils/http/api_error_messages.dart';

void main() {
  setUp(() {
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
  });

  tearDown(Get.reset);

  test('business errors use the active language instead of backend copy', () {
    expect(
      ApiErrorMessages.business(20001,
          detail: 'password error', message: 'PasswordError'),
      '密码错误',
    );
    Get.locale = const Locale('en', 'US');
    expect(
      ApiErrorMessages.business(20001,
          detail: '密码错误', message: 'PasswordError'),
      'The password is wrong',
    );
  });

  test('changing language immediately changes repeat error messages', () {
    for (final code in [20002, 20003, 20005, 20006, 20007, 20011, 20014]) {
      final chinese = ApiErrorMessages.business(code);
      Get.locale = const Locale('en', 'US');
      final english = ApiErrorMessages.business(code);
      expect(english, isNot(chinese));
      expect(english, isNot('$code'));
      Get.locale = const Locale('zh', 'CN');
      expect(ApiErrorMessages.business(code), chinese);
    }
  });

  test('registration closure depends on the endpoint', () {
    for (final path in [
      '/account/register',
      '/account/register/',
      'http://129.226.192.93:10008/account/register?mode=phone',
    ]) {
      expect(ApiErrorMessages.business(1002, path: path), '暂未开放注册');
    }
    expect(ApiErrorMessages.business(1002, path: '/account/login'), '1002'.tr);
    Get.locale = const Locale('en', 'US');
    expect(ApiErrorMessages.business(1002, path: '/account/register'),
        'Registration is currently unavailable');
  });

  test('empty fields resolve to their own localized prompts', () {
    const fields = {
      'account can not be empty': 'plsEnterAccount',
      'phoneNumber cannot be empty': 'plsEnterPhoneNumber',
      'email is required': 'plsEnterEmail',
      'password must not be empty': 'plsEnterPassword',
      'verifyCode can not be empty': 'plsEnterVerificationCode',
      'nickname can not be empty': 'nicknameCannotBeEmpty',
    };
    for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
      Get.locale = locale;
      for (final field in fields.entries) {
        expect(
            ApiErrorMessages.business(1001, detail: field.key), field.value.tr);
      }
      expect(ApiErrorMessages.business(1001, detail: 'invitationCode is empty'),
          'plsEnterInvitationCode'.tr.replaceAll('%s', '').trim());
    }
  });

  test('phone and email format details are localized', () {
    expect(
        ApiErrorMessages.business(1001, detail: 'invalid phoneNumber format'),
        'plsEnterRightPhone'.tr);
    Get.locale = const Locale('en', 'US');
    expect(ApiErrorMessages.business(1001, detail: 'email is not valid'),
        'Please enter a valid email address');
    expect(
        ApiErrorMessages.business(1001, detail: 'phone/email format invalid'),
        'Please enter a valid phone or email address');
  });

  test('unrecognized validation details are not exposed or guessed', () {
    for (final detail in [
      'invalid operationID',
      'json: cannot unmarshal string into Go field phoneNumber',
      'password service connection failed: goroutine /tmp/server/account.go',
      'failed to write account',
    ]) {
      expect(ApiErrorMessages.business(1001, detail: detail), '1001'.tr);
    }
  });

  test('message is inspected only when detailed validation reason is empty',
      () {
    expect(ApiErrorMessages.business(1001, message: 'password cannot be empty'),
        'plsEnterPassword'.tr);
    expect(
      ApiErrorMessages.business(1001,
          detail: 'unsupported option', message: 'password cannot be empty'),
      '1001'.tr,
    );
  });

  test('nickname business codes retain specific current-language copy', () {
    expect(ApiErrorMessages.business(20018), 'nicknameAlreadyUsed'.tr);
    Get.locale = const Locale('en', 'US');
    expect(ApiErrorMessages.business(20019), 'nicknameUpdateTooFrequent'.tr);
  });

  test('token failures ask to sign in again in the current language', () {
    for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
      Get.locale = locale;
      for (final code in [
        1501,
        1502,
        1503,
        1504,
        1505,
        1506,
        1507,
        20101,
        100010
      ]) {
        expect(ApiErrorMessages.business(code), 'apiSessionExpired'.tr);
      }
    }
  });

  test('unknown errors keep the code and hide server details', () {
    expect(
      ApiErrorMessages.business(987654,
          detail: 'goroutine /tmp/private.go password=secret',
          message: 'Internal server exception'),
      '请求失败，请稍后重试（错误码：987654）',
    );
    Get.locale = const Locale('en', 'US');
    expect(ApiErrorMessages.business(987654, detail: '服务内部错误'),
        'The request failed (code: 987654). Please try again later.');
  });

  test('code 20008 describes verification attempts rather than sends', () {
    expect(ApiErrorMessages.business(20008), '验证码校验次数达到上限');
    Get.locale = const Locale('en', 'US');
    expect(ApiErrorMessages.business(20008),
        'You have reached the verification attempt limit');
  });

  test('transport and successful envelopes with failed results stay localized',
      () {
    expect(ApiErrorMessages.timeout, '请求超时，请稍后重试');
    expect(ApiErrorMessages.captchaNotPassed, '人机验证未通过，请重试');
    expect(ApiErrorMessages.codeNotSent, '验证码未发送成功，请稍后重试');
    Get.locale = const Locale('en', 'US');
    expect(
        ApiErrorMessages.timeout, 'The request timed out. Please try again.');
    expect(ApiErrorMessages.captchaNotPassed,
        'Human verification failed. Please try again.');
    expect(ApiErrorMessages.codeNotSent,
        'The verification code was not sent. Please try again later.');
  });

  test('generic not-found error does not leave a format placeholder', () {
    expect(ApiErrorMessages.business(1004), '请求的内容不存在');
    Get.locale = const Locale('en', 'US');
    expect(ApiErrorMessages.business(1004),
        'The requested content does not exist.');
  });

  test('translations work before the app installs its translation table', () {
    Get.clearTranslations();
    expect(ApiErrorMessages.business(20001), '密码错误');
    Get.locale = const Locale('en', 'US');
    expect(ApiErrorMessages.business(20001), 'The password is wrong');
  });
}
