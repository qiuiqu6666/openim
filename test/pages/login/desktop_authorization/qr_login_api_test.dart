import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/login/desktop_authorization/data/qr_login_api.dart';
import 'package:openim/pages/login/desktop_authorization/data/desktop_authorization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final id = 'a' * 43;
  final nonce = 'n' * 43;
  late Dio dio;
  late QrLoginApi api;
  late List<RequestOptions> requests;
  var code = 0;
  late DateTime expiresAt;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'a', 'chatToken': 'mobile-token', 'imToken': 'im-token'}));
    requests = [];
    code = 0;
    expiresAt = DateTime.now().add(const Duration(minutes: 2));
    dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'errCode': code,
        'errMsg': 'private data must not be surfaced',
        'data': code != 0
            ? null
            : request.path.endsWith('/scan')
                ? {
                    'sessionID': id,
                    'confirmNonce': nonce,
                    'deviceName': 'PC',
                    'platform': 3,
                    'verificationRequired': true,
                    'expiresAt': expiresAt.millisecondsSinceEpoch,
                  }
                : {
                    'state': request.path.endsWith('/confirm')
                        ? 'approved'
                        : 'cancelled'
                  },
      }));
    }));
    api = QrLoginApi(transport: dio, baseUrl: 'https://example.test');
  });
  test('scan confirm reject use mobile header and exact JSON contract',
      () async {
    await api.scan(id);
    expect((await api.confirm(id, verificationCode: '012345')).state,
        DesktopAuthorizationState.approved);
    await api.cancel(id);
    expect(requests.map((r) => r.uri.path), [
      '/account/qr-login/scan',
      '/account/qr-login/confirm',
      '/account/qr-login/reject'
    ]);
    expect(requests[1].data,
        {'sessionID': id, 'confirmNonce': nonce, 'verificationCode': '012345'});
    for (final request in requests) {
      expect(request.headers['token'], 'mobile-token');
      expect(request.uri.hasQuery, false);
      expect(request.followRedirects, false);
      expect(request.headers.containsKey('Authorization'), false);
    }
  });
  test('business errors on HTTP 200 are not success or raw server messages',
      () async {
    for (final failure in [202, 401, 403, 409, 410, 426, 429, 503]) {
      code = failure;
      await expectLater(
          api.scan(id),
          throwsA(
              isA<QrLoginFailure>().having((e) => e.code, 'code', failure)));
    }
  });
  test('account switch cannot reuse scan nonce', () async {
    await api.scan(id);
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'b', 'chatToken': 'other', 'imToken': 'other'}));
    await expectLater(api.confirm(id, verificationCode: '012345'),
        throwsA(isA<QrLoginFailure>()));
    expect(requests.length, 1);
  });
  test('expired server session is rejected before confirmation', () async {
    expiresAt = DateTime.now().subtract(const Duration(seconds: 1));
    await expectLater(api.scan(id),
        throwsA(isA<QrLoginFailure>().having((e) => e.code, 'code', 410)));
    await expectLater(api.confirm(id, verificationCode: '012345'),
        throwsA(isA<QrLoginFailure>()));
    expect(requests.length, 1);
  });
  test('session expiring after scan cannot send confirmation', () async {
    expiresAt = DateTime.now().add(const Duration(milliseconds: 100));
    await api.scan(id);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await expectLater(api.confirm(id, verificationCode: '012345'),
        throwsA(isA<QrLoginFailure>().having((e) => e.code, 'code', 410)));
    expect(requests.length, 1);
  });
  test('HTTP backup and local shield support scan confirm and reject',
      () async {
    for (final baseUrl in [
      'http://example.test:10008',
      'http://127.0.0.1:10008'
    ]) {
      final service = QrLoginApi(transport: dio, baseUrl: baseUrl);
      await service.scan(id);
      expect((await service.confirm(id, verificationCode: '012345')).state,
          DesktopAuthorizationState.approved);
      await service.cancel(id);
      expect(requests.last.uri.origin, baseUrl);
    }
    expect(requests.length, 6);
  });
  test('invalid service addresses are rejected before sending credentials',
      () async {
    for (final baseUrl in [
      'ftp://example.test',
      'http:///path',
      'http://user:password@example.test',
      'http://example.test?token=value',
      'http://example.test#fragment',
    ]) {
      await expectLater(QrLoginApi(transport: dio, baseUrl: baseUrl).scan(id),
          throwsA(isA<QrLoginFailure>()));
    }
    expect(requests, isEmpty);
  });
  test('invalid code and desktop status are not sent', () async {
    await api.scan(id);
    await expectLater(api.confirm(id, verificationCode: '123'),
        throwsA(isA<QrLoginFailure>()));
    await expectLater(
        api.status(id), throwsA(isA<DesktopAuthorizationUnavailable>()));
    expect(requests.length, 1);
  });
}
