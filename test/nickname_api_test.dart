import 'package:dio/dio.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';
// Test double for the device plugin used by the existing API logger.
// ignore: depend_on_referenced_packages
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestWindowsInfo implements WindowsDeviceInfo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDeviceInfoPlatform extends DeviceInfoPlatform {
  @override
  Future<BaseDeviceInfo> deviceInfo() async => _TestWindowsInfo();
}

void main() {
  testWidgets('nickname requests preserve original text and use server errors',
      (tester) async {
    final originalPlatform = DeviceInfoPlatform.instance;
    DeviceInfoPlatform.instance = _TestDeviceInfoPlatform();
    addTearDown(() => DeviceInfoPlatform.instance = originalPlatform);
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current-user',
      'chatToken': 'chat-token',
      'imToken': 'im-token',
    }));
    await tester.pumpWidget(GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      builder: EasyLoading.init(),
      home: const Scaffold(body: SizedBox()),
    ));
    await tester.pumpAndSettle();
    final originalDio = dio;
    dio = Dio();
    addTearDown(() {
      dio = originalDio;
      Get.reset();
    });
    final requests = <RequestOptions>[];
    var response = <String, dynamic>{'errCode': 0};
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(
          Response(requestOptions: request, statusCode: 200, data: response));
    }));

    await tester.runAsync(() async {
      for (final nickname in ['Alice', 'alice', ' Alice ', ' ']) {
        // Success has no data. Identical retries must still reach the server.
        await Apis.updateUserInfo(userID: 'current-user', nickname: nickname);
        expect(requests.last.path, endsWith('/user/update'));
        expect(requests.last.data['nickname'], {'value': nickname});
        expect(requests.last.data['userID'], 'current-user');
        expect(requests.last.headers['token'], 'chat-token');
      }
      await Apis.updateUserInfo(userID: 'current-user', faceURL: 'avatar');
      expect(requests.last.data.containsKey('nickname'), false);

      for (final code in [20018, 20019, 1001]) {
        response = {
          'errCode': code,
          'errMsg': 'Rejected',
          'errDlt': code == 1001 ? 'nickname can not be empty' : ''
        };
        await expectLater(
          Apis.updateUserInfo(userID: 'current-user', nickname: ' Alice '),
          throwsA(isA<(int, String?)>().having((e) => e.$1, 'code', code)),
        );
      }
      response = {'errCode': 0};
      await Apis.updateUserInfo(userID: 'current-user', nickname: ' Alice ');
      expect(requests.last.data['nickname'], {'value': ' Alice '});

      response = {
        'errCode': 0,
        'data': {'userID': 'registered'}
      };
      for (final nickname in [' Alice ', 'alice', '']) {
        await Apis.register(
            nickname: nickname,
            password: 'Password123',
            verificationCode: '666666');
        expect(requests.last.path, endsWith('/account/register'));
        expect(requests.last.data['user']['nickname'], nickname);
      }
      response = {
        'errCode': 20018,
        'errMsg': 'NicknameAlreadyUsed',
        'errDlt': ''
      };
      await expectLater(
          Apis.register(
              nickname: 'Alice',
              password: 'Password123',
              verificationCode: '666666'),
          throwsA(isA<(int, String?)>()));
    });
    await EasyLoading.dismiss(animation: false);
    await tester.pumpAndSettle();
    expect(HttpUtil.businessErrorMessage(ApiResp.fromJson({'errCode': 20018})),
        '昵称已被占用，请换一个昵称');
    expect(HttpUtil.businessErrorMessage(ApiResp.fromJson({'errCode': 20019})),
        '7天内只能修改一次昵称，请稍后再试');
    expect(
        HttpUtil.businessErrorMessage(ApiResp.fromJson({
          'errCode': 1001,
          'errDlt': 'nickname can not be empty',
        })),
        '昵称不能为空');
  });
}
