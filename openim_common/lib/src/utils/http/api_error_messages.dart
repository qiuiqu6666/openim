import 'package:get/get.dart';

import '../../res/lang/en_US.dart' as english;
import '../../res/lang/zh_CN.dart' as chinese;

/// Converts protocol errors into copy for the app's current language.
/// Server details are inspected only for known validation reasons, never shown.
abstract final class ApiErrorMessages {
  static bool isSessionError(int code) =>
      (code >= 1501 && code <= 1507) || code == 20101 || code == 100010;

  static String business(
    int code, {
    String? path,
    String detail = '',
    String message = '',
  }) {
    if (isSessionError(code)) {
      return sessionExpired;
    }
    if (code == 1002 && _isRegistration(path)) {
      return _text('apiRegistrationUnavailable');
    }
    if (code == 1001) {
      return _validationMessage(detail.isNotEmpty ? detail : message) ??
          _text('1001');
    }
    if (code == 20018) return _text('nicknameAlreadyUsed');
    if (code == 20019) return _text('nicknameUpdateTooFrequent');
    if (code == 20081) return _text('apiNewDeviceVerificationRequired');
    if (code == 20082) return _text('apiNewDevicePhoneNotBound');
    if (code == 20083) return _text('apiLoginDeviceIDInvalid');
    if (code == 1004) return _text('apiContentNotFound');

    final key = code.toString();
    final translated = _text(key);
    return translated == key ? unknown(code) : translated;
  }

  static String get requestFailed => _text('apiRequestFailed');
  static String get timeout => _text('apiRequestTimeout');
  static String get network => _text('apiNetworkUnavailable');
  static String get serviceUnavailable => _text('apiServiceUnavailable');
  static String get captchaNotPassed => _text('apiCaptchaNotPassed');
  static String get codeNotSent => _text('apiVerificationCodeNotSent');
  static String get invalidResponse => _text('apiInvalidResponse');
  static String get requestCancelled => _text('apiRequestCancelled');
  static String get sessionExpired => _text('apiSessionExpired');

  static String unknown(int code) =>
      _text('apiRequestFailedWithCode').replaceAll('@code', '$code');

  static bool _isRegistration(String? path) {
    if (path == null) return false;
    final requestPath = Uri.tryParse(path)?.path ?? path;
    return requestPath.replaceFirst(RegExp(r'/+$'), '') == '/account/register';
  }

  static String? _validationMessage(String reason) {
    final normalized = reason.toLowerCase().replaceAll(RegExp(r'[_\s-]+'), ' ');
    final compact = normalized.replaceAll(' ', '');
    final empty = _containsAny(normalized, const [
      'can not be empty',
      'cannot be empty',
      'must not be empty',
      'is empty',
      'is required',
      'required field',
      'missing',
      '不能为空',
      '为空',
      '未填写',
    ]);
    final invalid = _containsAny(normalized, const [
      'invalid',
      'format',
      'not valid',
      'malformed',
      '格式',
      '不正确',
    ]);
    if (!empty && !invalid) return null;

    final phone = _containsAny(compact, const ['phone', 'mobile', '手机号']);
    final email = _containsAny(compact, const ['email', '邮箱']);
    if (phone && email) {
      return _text(empty ? 'plsEnterAccount' : 'plsEnterRightPhoneOrEmail');
    }
    if (_containsAny(compact, const ['nickname', '昵称'])) {
      return empty ? _text('nicknameCannotBeEmpty') : null;
    }
    if (_containsAny(compact, const ['invitation', 'invitecode', '邀请码'])) {
      return empty
          ? _text('plsEnterInvitationCode').replaceAll('%s', '').trim()
          : _text('apiInvitationCodeInvalid');
    }
    if (_containsAny(
        compact, const ['verifycode', 'verificationcode', '验证码'])) {
      return _text(
          empty ? 'plsEnterVerificationCode' : 'apiVerificationCodeInvalid');
    }
    if (_containsAny(compact, const ['password', 'pwd', '密码'])) {
      return _text(empty ? 'plsEnterPassword' : 'wrongPasswordFormat');
    }
    if (phone) {
      return _text(empty ? 'plsEnterPhoneNumber' : 'plsEnterRightPhone');
    }
    if (email) return _text(empty ? 'plsEnterEmail' : 'plsEnterRightEmail');
    if (_containsAny(compact, const ['account', 'username', 'userid', '账号'])) {
      return _text(empty ? 'plsEnterAccount' : 'plsEnterRightAccount');
    }
    return null;
  }

  static bool _containsAny(String value, List<String> keywords) =>
      keywords.any(value.contains);

  static String _text(String key) {
    final translated = key.tr;
    if (translated != key) return translated;
    // Keep shared callers useful before GetMaterialApp has installed its table.
    final fallback =
        Get.locale?.languageCode == 'zh' ? chinese.zh_CN : english.en_US;
    return fallback[key] ?? key;
  }
}
