import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/server_nodes/manual_node_switch_runtime.dart';
import 'package:openim/core/server_nodes/manual_node_switch_service.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends IMController {
  final calls = <String>[];
  bool connectionWorks = true;
  @override
  // Test owner does not start the native SDK automatically.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<void> logout() async {
    calls.add('logout');
  }

  @override
  Future<bool> initOpenIM({bool notifyStartup = true}) async {
    expect(notifyStartup, isFalse);
    calls.add('init:${Config.imApiUrl}:${Config.imWsUrl}');
    Logger().sdkIsInited = true;
    return true;
  }

  @override
  Future<void> login(String userID, String token) async {
    calls.add('login:$userID');
    expect(token, 'im-token');
    imSdkStatus(connectionWorks
        ? IMSdkStatus.connectionSucceeded
        : IMSdkStatus.connectionFailed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _IM logic;
  setUp(() async {
    Get.testMode = true;
    Get.put<AppController>(_App());
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'user',
      'imToken': 'im-token',
      'chatToken': 'chat-token',
    }));
    logic = _IM();
    Get.put<IMController>(logic);
    Logger().sdkIsInited = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_openim_sdk'),
            (call) async {
      expect(call.method, 'unInitSDK');
      logic.calls.add('uninit');
      return null;
    });
  });
  tearDown(() async {
    await logic.imSdkStatusPublishSubject.close();
    await logic.imSdkStatusSubject.close();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_openim_sdk'), null);
  });
  test('route switch orders SDK teardown init login and preserves credentials',
      () async {
    await ManualNodeSwitchRuntime.reconnect(NodeEndpoint.direct, () => true);
    expect(logic.calls, [
      'logout',
      'uninit',
      'init:${NodeEndpoint.direct.imApi}:${NodeEndpoint.direct.imWs}',
      'login:user',
    ]);
    expect(Config.appAuthUrl, NodeEndpoint.direct.chatApi);
    expect(dio.options.baseUrl, NodeEndpoint.direct.imApi);
    expect(DataSp.userID, 'user');
    expect(DataSp.imToken, 'im-token');
    expect(DataSp.chatToken, 'chat-token');
  });
  test('login without a working connection is not success', () async {
    logic.connectionWorks = false;
    await expectLater(
        ManualNodeSwitchRuntime.reconnect(NodeEndpoint.direct, () => true),
        throwsA(NodeSwitchFailure.connectionFailed));
  });
}
