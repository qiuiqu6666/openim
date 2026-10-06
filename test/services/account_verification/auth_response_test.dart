import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _Responses implements HttpClientAdapter {
  dynamic body = {
    'errCode': 0,
    'data': {'ok': true}
  };
  int status = 200;
  DioExceptionType? failure;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    if (failure != null) {
      throw DioException(
          requestOptions: options,
          type: failure!,
          message: 'Internal transport detail');
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio original;
  late _Responses responses;
  setUp(() async {
    Get.testMode = true;
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    original = http.dio;
    http.dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    responses = _Responses();
    http.dio.httpClientAdapter = responses;
  });
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    http.dio.close(force: true);
    http.dio = original;
    Get.reset();
  });

  for (final path in [
    '/account/login',
    '/account/register',
    '/account/password/reset',
    '/account/code/send',
    '/account/code/verify'
  ]) {
    test('HTTP 200 business errors are rejected at $path', () async {
      responses.body = {
        'errCode': 20006,
        'errMsg': 'VerifyCodeMismatch',
        'errDlt': 'private backend detail',
        'data': {'ok': true}
      };
      Object? failure;
      try {
        await HttpUtil.post(path, showErrorToast: false);
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<(int, String?)>());
      expect((failure as (int, String?)).$1, 20006);
      expect(failure.$2, 'private backend detail');
      expect(HttpUtil.errorMessage(failure, path: path), '验证码不匹配');
      Get.locale = const Locale('en', 'US');
      final message = HttpUtil.errorMessage(failure, path: path);
      expect(message, '20006'.tr);
      expect(message, isNot(contains('private backend')));
    });
  }

  test('non-200 responses still use their JSON business error code', () async {
    responses.status = 403;
    responses.body = {
      'errCode': '1002',
      'errMsg': 'NoPermission',
      'errDlt': 'register user is disabled'
    };
    Object? failure;
    try {
      await HttpUtil.post('/account/register', showErrorToast: false);
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<(int, String?)>());
    expect(
        HttpUtil.errorMessage(failure!, path: '/account/register'), '暂未开放注册');
  });

  test('success returns payload while a missing envelope is rejected',
      () async {
    expect(await HttpUtil.post('/account/code/verify', showErrorToast: false),
        {'ok': true});
    responses.body = {'errCode': 0};
    expect(
        await HttpUtil.post('/account/password/reset', showErrorToast: false),
        isNull);
    responses.body = {
      'data': {'ok': true}
    };
    await expectLater(HttpUtil.post('/account/login', showErrorToast: false),
        throwsFormatException);
  });

  test('network errors preserve type and resolve language when displayed',
      () async {
    responses.failure = DioExceptionType.connectionTimeout;
    Object? failure;
    try {
      await HttpUtil.post('/account/login', showErrorToast: false);
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<DioException>());
    final chinese = HttpUtil.errorMessage(failure!);
    expect(chinese, contains('超时'));
    Get.locale = const Locale('en', 'US');
    expect(HttpUtil.errorMessage(failure), isNot(chinese));
    expect(
        HttpUtil.errorMessage(failure), isNot(contains('Internal transport')));
  });

  testWidgets('password reset business failure remains a failed request',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        builder: EasyLoading.init(),
        home: const Scaffold()));
    responses.body = {
      'errCode': 20007,
      'errMsg': 'VerifyCodeExpired',
    };
    await tester.runAsync(() async {
      await expectLater(
          Apis.resetPassword(
              areaCode: '+86',
              phoneNumber: '13800138000',
              password: 'password1',
              verificationCode: '123456'),
          throwsA(isA<(int, String?)>().having((e) => e.$1, 'code', 20007)));
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('20007'.tr), findsOneWidget);
  });

  testWidgets(
      'authenticated network failure keeps credentials and uses English',
      (tester) async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current',
      'chatToken': 'current-chat',
      'imToken': 'current-im',
    }));
    await tester.pumpWidget(GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('en', 'US'),
        builder: EasyLoading.init(),
        home: const Scaffold(body: Text('signed in'))));
    responses.failure = DioExceptionType.connectionTimeout;
    await tester.runAsync(() async {
      expect(await Apis.searchUserFullInfo(content: 'Alice'), isEmpty);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(DataSp.userID, 'current');
    expect(DataSp.chatToken, 'current-chat');
    expect(find.text('signed in'), findsOneWidget);
    expect(find.text(ApiErrorMessages.timeout), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('session owner receives one event and owns the expiry feedback',
      (tester) async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current',
      'chatToken': 'current-chat',
      'imToken': 'current-im',
    }));
    await tester.pumpWidget(GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('en', 'US'),
        builder: EasyLoading.init(),
        home: const Scaffold()));
    HttpUtil.init();
    responses.body = {'errCode': 1502, 'errMsg': 'TokenInvalidError'};
    final events = <int>[];
    final subscription = Apis.kickoffController.stream.listen((code) {
      events.add(code as int);
      // Simulate the owner clearing credentials before post() finishes.
      DataSp.removeLoginCertificate();
    });
    addTearDown(subscription.cancel);
    await tester.runAsync(() async {
      expect(await Apis.getUserFullInfo(userIDList: ['current']), isEmpty);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, [1502]);
    expect(EasyLoading.isShow, isFalse);
  });
}
