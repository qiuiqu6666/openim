import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import 'device_verification_code_result.dart';

/// Owns one password-login snapshot in memory. SMS confirmation preserves the
/// original identity, password proofs and device metadata instead of SMS login.
class PasswordDeviceLoginAttempt {
  PasswordDeviceLoginAttempt._(this._request);

  Map<String, dynamic> _request;

  Map<String, dynamic> get _activeRequest {
    if (_request.isEmpty) {
      throw StateError('Password login attempt was released');
    }
    return _request;
  }

  static Future<PasswordDeviceLoginAttempt> prepare({
    String? areaCode,
    String? phoneNumber,
    String? account,
    String? email,
    required String password,
  }) async =>
      PasswordDeviceLoginAttempt.fromRequest(await Apis.prepareLoginRequest(
        areaCode: areaCode,
        phoneNumber: phoneNumber,
        account: account,
        email: email,
        password: password,
      ));

  /// The payload must already have been prepared for the current attempt.
  /// Copies it so changes to a caller's form or map cannot change later proof.
  factory PasswordDeviceLoginAttempt.fromRequest(Map<String, dynamic> request) {
    const fields = {
      'account',
      'phoneNumber',
      'email',
      'password',
      'passwordPlaintext',
      'areaCode',
      'platform',
      'deviceID',
      'deviceName',
      'version',
    };
    final identities =
        ['account', 'phoneNumber', 'email'].where(request.containsKey).length;
    if (identities != 1 ||
        ['account', 'phoneNumber', 'email'].any((key) =>
            request.containsKey(key) &&
            (request[key] is! String ||
                (request[key] as String).trim().isEmpty)) ||
        request['password'] is! String ||
        !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(request['password'] as String) ||
        (request.containsKey('passwordPlaintext') &&
            (request['passwordPlaintext'] is! String ||
                (request['passwordPlaintext'] as String).isEmpty ||
                IMUtils.generateMD5(request['passwordPlaintext'] as String) !=
                    request['password'])) ||
        request['deviceID'] is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
            .hasMatch(request['deviceID'] as String) ||
        request['platform'] is! int ||
        request['deviceName'] is! String ||
        request['version'] is! String ||
        (request.containsKey('areaCode') && request['areaCode'] is! String) ||
        request.keys.any((key) => !fields.contains(key)) ||
        request.values.any(
            (value) => value is! String && value is! int && value != null)) {
      throw const FormatException('Invalid frozen password login request');
    }
    return PasswordDeviceLoginAttempt._(
        Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(request)));
  }

  String? get phoneNumber => _request['phoneNumber'] as String?;
  String? get areaCode => _request['areaCode'] as String?;

  Future<LoginCertificate> submit({
    String? verifyCode,
    bool Function()? isCurrent,
  }) {
    final request = _activeRequest;
    if (verifyCode != null && !RegExp(r'^\d{6}$').hasMatch(verifyCode)) {
      throw const FormatException('Invalid device verification code');
    }
    return Apis.loginWithRequest(
      {...request, if (verifyCode != null) 'verifyCode': verifyCode},
      isCurrent: isCurrent,
      showErrorToast: false,
    );
  }

  Future<DeviceVerificationCodeResult> sendCode({
    required String areaCode,
    required String phoneNumber,
    required String captchaVerifyParam,
    bool Function()? isCurrent,
  }) async {
    final request = _activeRequest;
    if (isCurrent != null && !isCurrent()) {
      throw StateError('Login attempt is no longer current');
    }
    if (areaCode.trim().isEmpty ||
        phoneNumber.trim().isEmpty ||
        captchaVerifyParam.isEmpty) {
      throw const FormatException('Incomplete device verification request');
    }
    final data = await HttpUtil.post(
      Urls.getVerificationCode,
      data: {
        'usedFor': 3,
        'areaCode': areaCode.trim(),
        'phoneNumber': phoneNumber.trim(),
        'platform': request['platform'],
        'deviceID': request['deviceID'],
        'captchaVerifyParam': captchaVerifyParam,
      },
      withoutToken: true,
      requestOperationID: const Uuid().v4(),
      options: Options(contentType: Headers.jsonContentType),
      showErrorToast: false,
    );
    return DeviceVerificationCodeResult.fromJson(data);
  }

  /// Release the credential snapshot when the route's owner ends this attempt.
  /// Any request already sent owns only its own copy; late results still need
  /// the caller's account/route guard before completing a session.
  void close() => _request = const {};

  @override
  String toString() => 'PasswordDeviceLoginAttempt(redacted)';
}
