import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/account_security/email/email_account_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previous;
  late Dio client;
  late OpenIMEmailAccountService service;
  final requests = <RequestOptions>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'owner';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'owner',
      'chatToken': 'synthetic-token',
      'imToken': 'synthetic-im'
    }));
    previous = http.dio;
    requests.clear();
    client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'errCode': 0,
          'data': request.path.endsWith('/code/send')
              ? {
                  'captchaVerifyResult': true,
                  'bizResult': true,
                  'retryAfter': 60
                }
              : {'email': 'new@example.test'},
        }));
      }));
    http.dio = client;
    service = OpenIMEmailAccountService();
  });
  tearDown(() {
    http.dio = previous;
    client.close();
    OpenIM.iMManager.userID = '';
  });

  test('email code and binding use authenticated purpose-specific contracts',
      () async {
    expect(
        (await service.send(' New@Example.test ', 'bind', 'synthetic-captcha'))
            .sent,
        isTrue);
    expect(requests.single.path, endsWith('/account/email/code/send'));
    expect(requests.single.data, containsPair('email', 'new@example.test'));
    expect(requests.single.data, containsPair('purpose', 'bind'));
    expect(requests.single.headers['token'], 'synthetic-token');
    await service.save(
        changing: false,
        email: 'New@Example.test',
        code: '123456',
        oldCode: '',
        password: 'Example123');
    expect(requests.last.path, endsWith('/account/email/bind'));
    expect(requests.last.data,
        containsPair('password', IMUtils.generateMD5('Example123')));
    expect(requests.last.data, containsPair('verifyCode', '123456'));
    expect(requests.last.data.containsKey('passwordPlaintext'), isFalse);
    expect(requests.last.data.containsKey('phoneNumber'), isFalse);
  });
  test('changing sends both proofs and never changes the phone', () async {
    await service.save(
        changing: true,
        email: 'new@example.test',
        code: '123456',
        oldCode: '654321',
        password: '');
    expect(requests.single.path, endsWith('/account/email/change'));
    expect(requests.single.data, containsPair('oldVerifyCode', '654321'));
    expect(requests.single.data.containsKey('password'), isFalse);
    expect(requests.single.data.containsKey('phoneNumber'), isFalse);
  });
  test('a replaced session cannot send or modify an email', () async {
    OpenIM.iMManager.userID = 'other';
    await expectLater(
        service.send('new@example.test', 'bind', 'captcha'), throwsStateError);
    await expectLater(
        service.save(
            changing: false,
            email: 'new@example.test',
            code: '123456',
            oldCode: '',
            password: 'Example123'),
        throwsStateError);
    expect(requests, isEmpty);
  });
}
