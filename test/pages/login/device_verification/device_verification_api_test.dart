import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/login/device_verification/data/device_verification_code_result.dart';
import 'package:openim/pages/login/device_verification/data/password_device_login_attempt.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = 'a62f645a-139c-4ef3-a108-f3667eef8764';
final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false);

class _HTTP implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final responses = <Map<String, dynamic>>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    requests.add(options);
    if (responses.isEmpty) throw StateError('Unexpected HTTP request');
    return ResponseBody.fromString(jsonEncode(responses.removeAt(0)), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  void reply(dynamic data, {int code = 0}) => responses.add({
        'errCode': code,
        'errMsg': '',
        'errDlt': '',
        if (data != null) 'data': data,
      });
}

Map<String, dynamic> _passwordRequest({String identity = 'account'}) => {
      identity: identity == 'phoneNumber'
          ? '13800138000'
          : identity == 'email'
              ? 'user@example.com'
              : 'public-account',
      if (identity == 'phoneNumber') 'areaCode': '+86',
      'password': IMUtils.generateMD5('password'),
      'deviceID': _device,
      'deviceName': 'Test phone',
      'platform': 2,
      'version': '1.0.0',
    };

const _certificate = {
  'userID': 'verified-user',
  'chatToken': 'verified-chat',
  'imToken': 'verified-im',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _HTTP adapter;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'deviceID': _device});
    await DataSp.init();
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    http.dio = Dio();
    HttpUtil.init();
    // A stale authenticated default must never leak to either pre-login API.
    http.dio.options.headers['token'] = 'previous-session-token';
    adapter = _HTTP();
    http.dio.httpClientAdapter = adapter;
  });
  tearDown(() => http.dio.close(force: true));

  test('login preparation keeps one identity and a stable persisted device',
      () async {
    for (final identity in ['phoneNumber', 'account', 'email']) {
      final request = await Apis.prepareLoginRequest(
        areaCode: '+86',
        phoneNumber: identity == 'phoneNumber' ? '13800138000' : null,
        account: identity == 'account' ? 'public-account' : null,
        email: identity == 'email' ? 'user@example.com' : null,
        password: 'password',
      );
      expect(request[identity], _passwordRequest(identity: identity)[identity]);
      for (final other in ['phoneNumber', 'account', 'email']) {
        if (other != identity) expect(request[other], isNull);
      }
      expect(request['password'], IMUtils.generateMD5('password'));
      expect(request['deviceID'], _device);
      expect(request['platform'], isA<int>());
      expect(request['deviceName'], isA<String>());
      expect(request['version'], '1.0.0+1');
      expect(() => request['password'] = 'changed', throwsUnsupportedError);
    }
    expect(adapter.requests, isEmpty);
  });

  test('invalid legacy device IDs are repaired once and survive preparation',
      () async {
    for (final legacy in ['', 'legacy-device', 123]) {
      SharedPreferences.setMockInitialValues({'deviceID': legacy});
      await DataSp.init();
      final ids = await Future.wait([
        DataSp.ensureLoginDeviceID(),
        DataSp.ensureLoginDeviceID(),
        DataSp.ensureLoginDeviceID(),
      ]);
      expect(ids.toSet(), hasLength(1));
      expect(_uuid.hasMatch(ids.first), isTrue);
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('deviceID'), ids.first);
      final request = await Apis.prepareLoginRequest(
          account: 'public-account', password: 'password');
      expect(request['deviceID'], ids.first);
    }
  });

  test('20081 is a business challenge without saving any credentials',
      () async {
    final attempt = PasswordDeviceLoginAttempt.fromRequest(_passwordRequest());
    adapter.reply(null, code: 20081);
    await expectLater(attempt.submit(),
        throwsA(predicate((e) => e is (int, String?) && e.$1 == 20081)));
    expect(DataSp.getLoginCertificate(), isNull);
    expect(adapter.requests.single.headers['token'], isNull);
    expect(
        _uuid.hasMatch(adapter.requests.single.headers['operationID']), isTrue);
    expect(adapter.requests.single.contentType, Headers.jsonContentType);
  });

  test(
      'legacy HTTP encrypted retry prevents redirects and retains frozen proof',
      () async {
    await DataSp.putServerConfig({'authUrl': 'http://129.226.192.93:10008'});
    final request = await Apis.prepareLoginRequest(
        account: 'public-account', password: 'Original-password-123');
    final attempt = PasswordDeviceLoginAttempt.fromRequest(request);
    adapter.reply(null, code: 20084);
    adapter.reply(null, code: 20081);
    await expectLater(attempt.submit(), throwsA(anything));
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.data['passwordPlaintext'], isNull);
    expect(adapter.requests.last.data['passwordPlaintext'],
        startsWith('rsa-oaep-sha256-v1:'));
    expect(adapter.requests.last.data['passwordPlaintext'],
        isNot(contains('Original-password-123')));
    expect(adapter.requests.every((r) => !r.followRedirects), isTrue);
    adapter.reply(null, code: 20084);
    adapter.reply(_certificate);
    await attempt.submit(verifyCode: '123456');
    expect(adapter.requests.last.data['verifyCode'], '123456');
    expect(adapter.requests.last.data['account'], 'public-account');
    expect(adapter.requests.last.data['phoneNumber'], isNull);
    expect(adapter.requests.last.data['password'], request['password']);
    expect(adapter.requests.every((r) => r.headers['token'] == null), isTrue);
    attempt.close();
    expect(() => attempt.submit(), throwsStateError);
  });

  test('verification resubmits the frozen password/device request with code',
      () async {
    final original = _passwordRequest();
    final frozen = Map<String, dynamic>.from(original);
    final attempt = PasswordDeviceLoginAttempt.fromRequest(original);
    original['password'] = 'an unrelated changed password';
    original['account'] = 'another account';
    adapter.reply(null, code: 20081);
    await expectLater(attempt.submit(), throwsA(anything));
    adapter.reply(_certificate);
    final certificate = await attempt.submit(verifyCode: '123456');
    expect(certificate.userID, 'verified-user');
    expect(adapter.requests.first.data, frozen);
    expect(adapter.requests.last.data, {...frozen, 'verifyCode': '123456'});
    expect(adapter.requests.last.data['password'], frozen['password']);
    expect(adapter.requests.last.data['phoneNumber'], isNull);
    expect(adapter.requests.last.data['trusted'], isNull);
    expect(adapter.requests.last.data['ip'], isNull);
    expect(DataSp.getLoginCertificate(), isNull);
    final operations = adapter.requests
        .map((request) => request.headers['operationID'])
        .toList();
    expect(operations.toSet(), hasLength(2));
    expect(
        operations.every((id) => id is String && _uuid.hasMatch(id)), isTrue);
    expect(adapter.requests.every((r) => r.headers['token'] == null), isTrue);
  });

  test(
      'SMS request uses login purpose and the same device without account data',
      () async {
    final attempt = PasswordDeviceLoginAttempt.fromRequest(_passwordRequest());
    adapter.reply({
      'captchaVerifyResult': true,
      'bizResult': true,
      'retryAfter': 17,
    });
    final result = await attempt.sendCode(
      areaCode: '+86',
      phoneNumber: '13800138000',
      captchaVerifyParam: 'real-slider-proof',
    );
    expect(result.sent, isTrue);
    expect(result.retryAfter, 17);
    final request = adapter.requests.single;
    expect(request.uri.path, '/account/code/send');
    expect(request.data, {
      'usedFor': 3,
      'areaCode': '+86',
      'phoneNumber': '13800138000',
      'platform': 2,
      'deviceID': _device,
      'captchaVerifyParam': 'real-slider-proof',
    });
    expect(request.headers['token'], isNull);
    expect(_uuid.hasMatch(request.headers['operationID']), isTrue);
    expect(request.contentType, Headers.jsonContentType);
  });

  test('code send requires two actual true booleans in the response', () async {
    final attempt = PasswordDeviceLoginAttempt.fromRequest(_passwordRequest());
    for (final flags in [
      <String, dynamic>{},
      {'captchaVerifyResult': true},
      {'bizResult': true},
      {'captchaVerifyResult': 'true', 'bizResult': true},
      {'captchaVerifyResult': true, 'bizResult': 1},
      {'captchaVerifyResult': false, 'bizResult': true},
      {'captchaVerifyResult': true, 'bizResult': false},
    ]) {
      adapter.reply(flags);
      final result = await attempt.sendCode(
          areaCode: '+86',
          phoneNumber: '13800138000',
          captchaVerifyParam: 'proof');
      expect(result.sent, isFalse, reason: '$flags');
    }
    final operations = adapter.requests
        .map((request) => request.headers['operationID'])
        .toSet();
    expect(operations, hasLength(7));
  });

  test('invalid resend intervals never start an unbounded or negative timer',
      () {
    for (final retry in [-1, 86401, '60', 1.2]) {
      expect(
          () => DeviceVerificationCodeResult.fromJson({
                'captchaVerifyResult': true,
                'bizResult': true,
                'retryAfter': retry,
              }),
          throwsFormatException);
    }
    expect(DeviceVerificationCodeResult.fromJson({}).retryAfter, 60);
    expect(
        DeviceVerificationCodeResult.fromJson({
          'captchaVerifyResult': true,
          'bizResult': true,
          'retryAfter': 0,
        }).retryAfter,
        0);
  });

  test('each missing credential is rejected before a session can be used',
      () async {
    final attempt = PasswordDeviceLoginAttempt.fromRequest(_passwordRequest());
    for (final field in ['userID', 'chatToken', 'imToken']) {
      for (final value in [null, '', '   ', 1]) {
        adapter.reply({..._certificate, field: value});
        await expectLater(
            attempt.submit(verifyCode: '123456'), throwsFormatException);
        expect(DataSp.getLoginCertificate(), isNull);
      }
    }
  });
}
