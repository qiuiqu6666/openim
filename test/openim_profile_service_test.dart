import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/mine/settings/openim_profile_service.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _ProfileController extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'im_internal', account: 'cached99').obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('profile refresh synchronizes backend account and keeps SDK identity',
      () async {
    const sdk = MethodChannel('flutter_openim_sdk');
    final originalDio = http.dio;
    final controller = _ProfileController();
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sdk, null);
      http.dio.close(force: true);
      http.dio = originalDio;
      OpenIM.iMManager.userID = '';
      await DataSp.removeLoginCertificate();
      controller.onClose();
      Get.reset();
    });
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'im_internal',
      'chatToken': 'chat-token',
      'imToken': 'im-token',
    }));
    OpenIM.iMManager.userID = 'im_internal';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      expect(call.method, 'getSelfUserInfo');
      return jsonEncode(UserInfo(
        userID: 'im_internal',
        ex: '{"signature":"hello"}',
      ).toJson());
    });
    String? publicAccount = '990001';
    final requests = <RequestOptions>[];
    http.dio = Dio();
    http.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'errCode': 0,
            'data': {
              'users': [
                {
                  'userID': 'im_internal',
                  'account': publicAccount,
                  'nickname': 'Profile',
                },
              ],
            },
          },
        ));
      },
    ));
    final service = OpenIMProfileService(controller);
    await service.refresh();
    expect(controller.userInfo.value.account, '990001');
    expect(controller.userInfo.value.userID, 'im_internal');
    expect(OpenIM.iMManager.userID, 'im_internal');
    expect(DataSp.userID, 'im_internal');
    expect(controller.userInfo.value.ex, '{"signature":"hello"}');
    expect(requests.single.data['userIDs'], ['im_internal']);
    expect(requests.single.headers['token'], 'chat-token');

    publicAccount = null;
    await service.refresh();
    expect(controller.userInfo.value.account, isNull);
    expect(controller.userInfo.value.userID, 'im_internal');
  });

  test('signature updates preserve unrelated SDK extension fields', () {
    final ex = OpenIMProfileService.signatureEx(
        '{"other":{"enabled":true},"signature":"old"}', 'new');
    expect(jsonDecode(ex), {
      'other': {'enabled': true},
      'signature': 'new',
    });
    expect(OpenIMProfileService.signatureFromEx(ex), 'new');
    expect(
        OpenIMProfileService.signatureFromEx(
            OpenIMProfileService.signatureEx(ex, '')),
        '');
  });
  test('unknown extension formats cannot be overwritten', () {
    for (final ex in ['opaque-data', '[]', 'null']) {
      expect(
          () => OpenIMProfileService.signatureEx(ex, 'new'), throwsA(anything));
      expect(OpenIMProfileService.signatureFromEx(ex), '');
    }
    expect(OpenIMProfileService.signatureFromEx(null), '');
    expect(jsonDecode(OpenIMProfileService.signatureEx(null, 'bio')),
        {'signature': 'bio'});
  });
  test('default settings remain unavailable', () {
    const service = StubSettingsService();
    expect(service.isBackendAvailable, isFalse);
    expect(service.isProfileBackendAvailable, isFalse);
  });
}
