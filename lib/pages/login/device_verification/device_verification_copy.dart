import 'package:flutter/material.dart';

/// Device-challenge copy follows the current widget locale, including previews.
class DeviceVerificationCopy {
  DeviceVerificationCopy(BuildContext context)
      : _locale = Localizations.localeOf(context);

  final Locale _locale;

  String _text(String zh, String en, {String? hant}) {
    if (_locale.languageCode == 'en') return en;
    final traditional = _locale.scriptCode == 'Hant' ||
        const ['TW', 'HK', 'MO'].contains(_locale.countryCode);
    return traditional ? hant ?? zh : zh;
  }

  String get title => _text('设备验证', 'Device Verification', hant: '設備驗證');
  String get subtitle => _text(
      '检测到新设备登录，需要验证身份', 'New device login detected. Verification is required.',
      hant: '檢測到新設備登入，需要驗證身份');
  String get smsHint => _text('验证码将发送到您账号绑定的手机号，请点击右侧发送',
      'A code will be sent to your bound phone number. Tap Send on the right',
      hant: '驗證碼將發送到您帳號綁定的手機號，請點擊右側發送');
  String sentTo(String phoneMasked) => _text('验证码将发送到 $phoneMasked',
      'The verification code will be sent to $phoneMasked',
      hant: '驗證碼將發送到 $phoneMasked');
  String get codeLabel => _text('验证码', 'Verification Code', hant: '驗證碼');
  String get codeHint => _text('6 位验证码', '6-digit code', hant: '6 位驗證碼');
  String get send => _text('发送', 'Send', hant: '發送');
  String get confirm => _text('确认登录', 'Confirm Login', hant: '確認登入');
  String get back => _text('返回', 'Back');
  String get phoneLabel => _text('绑定手机号', 'Bound phone number', hant: '綁定手機號');
  String get phoneHint => _text('请输入账号绑定的手机号', 'Enter your bound phone number',
      hant: '請輸入帳號綁定的手機號');
  String get phoneError =>
      _text('请输入正确的手机号', 'Enter a valid phone number', hant: '請輸入正確的手機號');
  String get sent => _text('验证码已发送', 'Verification code sent', hant: '驗證碼已發送');
  String get sendFailed =>
      _text('验证码发送失败，请稍后重试', 'Unable to send the code. Please try again later.',
          hant: '驗證碼發送失敗，請稍後重試');
}
