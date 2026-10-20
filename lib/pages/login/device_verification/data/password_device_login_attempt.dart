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
    String? method,
    bool Function()? isCurrent,
  }) {
    final request = _activeRequest;
    if (verifyCode != null && !RegExp(r'^\d{6}$').hasMatch(verifyCode)) {
      throw const FormatException('Invalid device verification code');
    }
    return Apis.loginWithRequest(
      {
        ...request,
        if (verifyCode != null) 'verifyCode': verifyCode,
        if (method != null) 'deviceVerificationMethod': method
      },
      isCurrent: isCurrent,
      showErrorToast: false,
    );
  }

  Future<dynamic> _deviceRequest(String path, Map<String, dynamic> extra,
      bool Function()? isCurrent) async {
    final endpoint = Uri.parse(Urls.login).resolve(path);
    if (isCurrent != null && !isCurrent()) {
      throw StateError('Login attempt is no longer current');
    }
    return LegacyPasswordLogin.submit(
      request: {..._activeRequest, ...extra},
      endpoint: endpoint,
      isCurrent: isCurrent,
      post: (payload) => HttpUtil.post(endpoint.toString(),
          data: payload,
          withoutToken: true,
          requestOperationID: const Uuid().v4(),
          options: Options(
              contentType: Headers.jsonContentType, followRedirects: false),
          showErrorToast: false),
    );
  }

  Future<List<String>> methods({bool Function()? isCurrent}) async {
    final data = await _deviceRequest('device/verification', {}, isCurrent);
    final methods = data is Map ? data['methods'] : null;
    if (methods is! List ||
        methods.any((v) => v != 'phone' && v != 'email') ||
        methods.toSet().length != methods.length) {
      throw const FormatException('Invalid device verification methods');
    }
    return List<String>.from(methods);
  }

  Future<DeviceVerificationCodeResult> sendCode({
    required String areaCode,
    required String phoneNumber,
    String captchaVerifyParam = '',
    String? method,
    bool Function()? isCurrent,
  }) async {
    final request = _activeRequest;
    if (isCurrent != null && !isCurrent()) {
      throw StateError('Login attempt is no longer current');
    }
    if (method != null) {
      if (method != 'phone' && method != 'email') {
        throw const FormatException('Invalid verification method');
      }
      final data = await _deviceRequest(
          'device/code/send',
          {
            'deviceVerificationMethod': method,
          },
          isCurrent);
      return DeviceVerificationCodeResult.fromJson(data);
    }
    if (captchaVerifyParam.isEmpty) {
      throw const FormatException('Incomplete device verification request');
    }
    final data = await HttpUtil.post(
      Urls.getVerificationCode,
      data: {
        'usedFor': 3,
        // Delivery follows the frozen login identity, never editable form data.
        // Account/email identities are resolved to a bound phone by the server.
        if (request.containsKey('account'))
          'loginAccount': request['account']
        else if (request.containsKey('email'))
          'loginEmail': request['email']
        else ...{
          'areaCode': request['areaCode'],
          'phoneNumber': request['phoneNumber'],
        },
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
