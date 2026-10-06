import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/login/device_verification/device_verification_flow.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/services/auth_credentials/auth_credentials_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_verification_test_app.dart';

const fixtureDeviceID = 'a62f645a-139c-4ef3-a108-f3667eef8764';
const fixtureCertificate = {
  'userID': 'verified-user',
  'chatToken': 'verified-chat',
  'imToken': 'verified-im',
};

class DeviceAuthHTTP implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final _responses = <Completer<ResponseBody>>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    _responses.add(response);
    return response.future;
  }

  void reply(int requestIndex, {int code = 0, dynamic data}) =>
      _responses[requestIndex].complete(ResponseBody.fromString(
        jsonEncode({
          'errCode': code,
          'errMsg': 'test response',
          'errDlt': '',
          if (data != null) 'data': data,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      ));
}

class DeviceAuthIM extends GetxController implements IMController {
  final logins = <(String, String)>[];
  @override
  Future<void> login(String account, String token) async {
    logins.add((account, token));
    OpenIM.iMManager.userID = account;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeviceAuthCache extends GetxController implements CacheController {
  int resets = 0;
  @override
  void resetCache() => resets++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeviceAuthCredentials extends AuthCredentialsStore {
  final saves = <({String account, String? password, bool remember})>[];
  @override
  Future<StoredAuthCredentials> load() async => const StoredAuthCredentials();
  @override
  Future<bool> saveSuccessful({
    required String account,
    required String areaCode,
    required int loginType,
    required String? password,
    required bool rememberPassword,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    saves.add((
      account: account,
      password: password,
      remember: rememberPassword,
    ));
    return true;
  }
}

class _Login extends LoginLogic {
  _Login(DeviceAuthCredentials store, DeviceCaptchaPresenter presenter)
      : super(credentialsStore: store, deviceCaptchaPresenter: presenter);
  @override
  void getPackageInfo() {}
}

Future<void> waitForAuth(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

class DeviceLoginFixture {
  final adapter = DeviceAuthHTTP();
  final im = DeviceAuthIM();
  final cache = DeviceAuthCache();
  late DeviceAuthCredentials credentials;
  late LoginLogic logic;
  Future<void>? pendingLogin;
  bool _closed = false;
  int captchaCalls = 0;

  Future<void> initialize(WidgetTester tester) async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({'deviceID': fixtureDeviceID});
    FlutterSecureStorage.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'none';
    Get.put<IMController>(im, permanent: true);
    Get.put<CacheController>(cache, permanent: true);
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    http.dio = Dio();
    HttpUtil.init();
    http.dio.httpClientAdapter = adapter;
    await mountDevicePage(
      tester,
      const Scaffold(body: Text('password entry')),
      getPages: [
        GetPage(
          name: AppRoutes.home,
          page: () => const Scaffold(body: Text('main ready')),
        ),
      ],
    );
    await tester.runAsync(() async {
      credentials = DeviceAuthCredentials();
      logic = _Login(credentials, (_, request) {
        captchaCalls++;
        return request('test-slider-proof');
      })
        ..onInit();
      await Future<void>.value();
    });
  }

  Future<void> startChallenge(WidgetTester tester,
      {String account = '13800138000'}) async {
    logic.phoneCtrl.text = account;
    logic.pwdCtrl.text = 'password';
    await tester.runAsync(() async {
      pendingLogin = logic.login();
      await waitForAuth(() => adapter.requests.length == 1);
      adapter.reply(0, code: 20081);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('设备验证'), findsOneWidget);
    expect(ModalRoute.of(tester.element(deviceCodeField))!.isCurrent, isTrue);
    expectNoSession();
  }

  void expectNoSession() {
    expect(DataSp.getLoginCertificate(), isNull);
    expect(im.logins, isEmpty);
    expect(cache.resets, 0);
    expect(credentials.saves, isEmpty);
    expect(find.text('main ready'), findsNothing);
  }

  Future<void> sendCode(WidgetTester tester,
      {bool sent = true, int retryAfter = 17}) async {
    final count = adapter.requests.length;
    expect(deviceSendButton(tester).onPressed, isNotNull);
    await tester.tap(deviceSend);
    await tester.pump();
    expect(captchaCalls, 1);
    await _pumpRequest(tester, count + 1);
    await tester.runAsync(() async {
      await waitForAuth(() => adapter.requests.length == count + 1);
      adapter.reply(count, data: {
        'captchaVerifyResult': true,
        'bizResult': sent,
        'retryAfter': retryAfter,
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await _pumpResponse(tester);
  }

  Future<int> submitCode(WidgetTester tester, {String code = '123456'}) async {
    final count = adapter.requests.length;
    await tester.enterText(deviceCodeField, code);
    await tester.pump();
    expect(deviceConfirmButton(tester).onPressed, isNotNull);
    await tester.tap(deviceConfirm);
    await tester.pump();
    await _pumpRequest(tester, count + 1);
    await tester.runAsync(
        () => waitForAuth(() => adapter.requests.length == count + 1));
    return count;
  }

  Future<void> respond(WidgetTester tester, int index,
      {int code = 0, dynamic data}) async {
    await tester.runAsync(() async {
      adapter.reply(index, code: code, data: data);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await _pumpResponse(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> finishLogin(WidgetTester tester) async {
    await tester.runAsync(() async => await pendingLogin);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 2500));
  }

  Future<void> dispose(WidgetTester tester) async {
    closeLogin();
    await clearDevicePage(tester);
    http.dio.close(force: true);
    Get.reset();
    Styles.isDark = false;
  }

  void closeLogin() {
    if (_closed) return;
    _closed = true;
    logic.onClose();
  }

  Future<void> _pumpRequest(WidgetTester tester, int count) async {
    // Dio's interceptor chain schedules zero-duration futures in the widget
    // clock when a tap starts the request. Pump them before entering runAsync.
    for (var i = 0; i < 10 && adapter.requests.length < count; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Future<void> _pumpResponse(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }
}
