import 'dart:convert';
import 'dart:typed_data';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/mine/settings/openim_profile_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller extends GetxController implements IMController {
  @override
  final userInfo =
      UserFullInfo(userID: 'me', phoneNumber: '13800000000', areaCode: '86')
          .obs;
  bool loggedOut = false;
  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'security calls authenticate with Chat token and preserve both phone codes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'me';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'me', 'imToken': 'im-token', 'chatToken': 'chat-token'}));
    await tester.pumpWidget(GetMaterialApp(
        builder: EasyLoading.init(),
        home: const Scaffold(),
        getPages: [
          GetPage(
              name: '/login', page: () => const Scaffold(body: Text('Login')))
        ]));
    final original = dio;
    dio = Dio();
    addTearDown(() {
      dio = original;
      Get.reset();
    });
    final requests = <RequestOptions>[];
    var result = <String, dynamic>{
      'errCode': 0,
      'data': {'captchaVerifyResult': true, 'bizResult': true, 'retryAfter': 60}
    };
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(
          Response(requestOptions: request, statusCode: 200, data: result));
    }));
    final controller = _Controller();
    final service = OpenIMProfileService(controller);
    await tester.runAsync(() async {
      result = {
        'errCode': 0,
        'data': {'feedbackID': 'fb_test'}
      };
      final feedbackID = await service.createFeedback(
          clientRequestID: 'request-1',
          type: 'bug',
          content: '  问题  ',
          attachments: [
            SettingsFeedbackAttachment(
                filename: 'image.png', bytes: Uint8List.fromList([1, 2, 3]))
          ],
          includeSDKLogs: true);
      expect(feedbackID, 'fb_test');
      expect(requests.last.path, endsWith('/feedback/create'));
      expect(requests.last.headers['token'], 'chat-token');
      final form = requests.last.data as FormData;
      final payload = jsonDecode(form.fields.single.value) as Map;
      expect(payload['content'], '问题');
      expect(payload['clientRequestID'], 'request-1');
      expect(payload['includeSDKLogs'], true);
      expect(payload.containsKey('userID'), false);
      expect(form.files.single.key, 'screenshots');
      expect(form.files.single.value.filename, 'image.png');
      result = {
        'errCode': 20049,
        'errMsg': 'FeedbackRateLimited',
        'data': {'retryAfter': 32}
      };
      await expectLater(
          service.createFeedback(
              clientRequestID: 'request-2',
              type: 'bug',
              content: '问题',
              attachments: [],
              includeSDKLogs: false),
          throwsA((20049, 'retryAfter:32')));
      result = {
        'errCode': 0,
        'data': {
          'records': [
            {
              'deviceID': 'other',
              'online': true,
              'trusted': true,
              'ipLocation': '地区'
            }
          ]
        }
      };
      final devices = await service.getLoginRecords();
      expect(devices.single['online'], true);
      expect(devices.single['trusted'], true);
      expect(devices.single['ipLocation'], '地区');
      expect(requests.last.data, isEmpty);
      result = {'errCode': 0};
      await service.removeDevice('other');
      expect(requests.last.path, endsWith('/account/device/remove'));
      expect(requests.last.data, {'deviceID': 'other'});
      await service.trustDevice('other', true);
      expect(requests.last.path, endsWith('/account/device/trust'));
      expect(requests.last.data, {'deviceID': 'other', 'trusted': true});
      await service.trustDevice('other', false);
      expect(requests.last.data['trusted'], false);
      await service.removeOtherDevices();
      expect(requests.last.path, endsWith('/account/device/remove_others'));
      expect(requests.last.data, isEmpty);
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.headers['token'], 'chat-token');
      }
      result = {'errCode': 20043, 'errMsg': 'DeviceSessionRequired'};
      await expectLater(service.removeOtherDevices(),
          throwsA((20043, 'DeviceSessionRequired')));
      result = {'errCode': 20042, 'errMsg': 'DeviceNotFound'};
      await expectLater(
          service.removeDevice('missing'), throwsA((20042, 'DeviceNotFound')));
      result = {
        'errCode': 0,
        'data': {
          'captchaVerifyResult': true,
          'bizResult': true,
          'retryAfter': 60
        }
      };
      await service.requestPhoneCode('13800000000',
          captchaVerifyParam: 'raw-proof');
      expect(requests.last.data['usedFor'], 2);
      expect(requests.last.data['captchaVerifyParam'], 'raw-proof');
      expect(requests.last.data['areaCode'], '+86');
      await service.requestNewPhoneCode('912345678',
          areaCode: '+886',
          invitationCode: 'invite',
          captchaVerifyParam: 'new-proof');
      expect(requests.last.data['usedFor'], 1);
      expect(requests.last.data['invitationCode'], 'invite');
      await service.changePhone(
          phone: '912345678',
          oldCode: '111111',
          newCode: '222222',
          areaCode: '+886');
      expect(requests.last.path, endsWith('/account/phone/change'));
      expect(requests.last.data, {
        'areaCode': '+886',
        'phoneNumber': '912345678',
        'oldVerifyCode': '111111',
        'newVerifyCode': '222222'
      });
      expect(service.securityPhone, '912345678');
      await service.bindPhone(
          phone: '13900000000', code: '333333', areaCode: '+86');
      expect(requests.last.path, endsWith('/account/phone/bind'));
      expect(requests.last.data.containsKey('oldVerifyCode'), false);
      await service.setTradePassword('123456');
      expect(requests.last.method, 'PUT');
      expect(requests.last.data, {'password': '123456'});
      await service.changeTradePassword(
          oldPassword: '123456', newPassword: '654321');
      expect(requests.last.data,
          {'currentPassword': '123456', 'password': '654321'});
      await service.requestTradePasswordCode(captchaVerifyParam: 'pay-proof');
      expect(requests.last.path, endsWith('/chat/fund/pay-password/code'));
      expect(requests.last.data, {'captchaVerifyParam': 'pay-proof'});
      for (final captcha in [false, true]) {
        result = {
          'errCode': 0,
          'data': {'captchaVerifyResult': captcha, 'bizResult': false}
        };
        final failed = await service.requestTradePasswordCode(
            captchaVerifyParam: 'failed-proof');
        expect(failed.captchaVerified, captcha);
        expect(failed.sent, false);
      }
      result = {'errCode': 20005, 'errMsg': 'frequency limit'};
      await expectLater(
          service.requestTradePasswordCode(captchaVerifyParam: 'limited-proof'),
          throwsA(isA<(int, String)>()));
      result = {'errCode': 0, 'data': {}};
      await expectLater(
          service.requestTradePasswordCode(
              captchaVerifyParam: 'legacy-response'),
          throwsFormatException);
      await service.resetTradePassword(code: '444444', password: '654321');
      expect(
          requests.last.data, {'verifyCode': '444444', 'password': '654321'});
      result = {
        'errCode': 0,
        'data': {'set': true}
      };
      expect(await service.hasTradePassword(), true);
      expect(requests.last.method, 'GET');
      result = {
        'errCode': 0,
        'data': {
          'records': [
            {'deviceName': 'Phone', 'loginTime': 1000}
          ]
        }
      };
      expect((await service.getLoginRecords()).single['deviceName'], 'Phone');
      expect(requests.last.data, {});
      for (final request in requests) {
        expect(request.headers['token'], 'chat-token');
        expect(request.headers['operationID'], isNotEmpty);
      }
      expect(requests.map((r) => r.headers['operationID']).toSet().length,
          requests.length);
      result = {'errCode': 20003, 'errMsg': 'PhoneAlreadyRegister'};
      await expectLater(
          service.requestNewPhoneCode('taken', captchaVerifyParam: 'raw-proof'),
          throwsA((20003, 'PhoneAlreadyRegister')));
      expect(requests.last.data['usedFor'], 1);
      await expectLater(
          service.changePhone(
              phone: 'taken', oldCode: '111111', newCode: '222222'),
          throwsA(isA<(int, String)>()));
      expect(service.securityPhone, '13900000000');
      result = {'errCode': 1001, 'errMsg': 'ArgsError'};
      await expectLater(
          service.changePassword(oldPassword: 'old', newPassword: 'New12345'),
          throwsA(isA<(int, String)>()));
      expect(requests.last.data['currentPassword'], IMUtils.generateMD5('old'));
      expect(
          requests.last.data['newPassword'], IMUtils.generateMD5('New12345'));
      await expectLater(
          service.changePasswordWithPhoneCode(
              phone: 'ignored', code: '555555', newPassword: 'New12345'),
          throwsA(isA<(int, String)>()));
      expect(requests.last.data.containsKey('currentPassword'), false);
      expect(requests.last.data['verifyCode'], '555555');
      expect(DataSp.chatToken, 'chat-token');
      result = {'errCode': 0};
      await service.changePasswordWithPhoneCode(
          phone: 'ignored', code: '555555', newPassword: 'New12345');
      expect(controller.loggedOut, true);
      expect(DataSp.chatToken, isNull);
    });
    await tester.pumpAndSettle();
  });
}

