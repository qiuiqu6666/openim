import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/splash/splash_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  int loginCalls = 0;
  final reply = Completer<void>();
  @override
  Future<void> login(String userID, String token) {
    loginCalls++;
    OpenIM.iMManager.userID = userID;
    return reply.future;
  }

  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Push extends GetxController implements PushController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  setUp(() async {
    Get.testMode = true;
    Get.put<AppController>(_App());
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'imToken': 'self-im',
      'chatToken': 'self-chat',
    }));
    OpenIM.iMManager.userID = 'self';
    Get.put<PushController>(_Push());
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
  });
  testWidgets(
      'auto-login navigates immediately without awaiting the first 400 conversations',
      (tester) async {
    final im = Get.put<IMController>(_IM()) as _IM;
    var listQueries = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      if (call.method == 'getConversationListSplit') {
        listQueries++;
        return Completer<String>().future;
      }
      throw StateError(call.method);
    });
    await tester.pumpWidget(GetMaterialApp(initialRoute: '/', getPages: [
      GetPage(name: '/', page: () => const Scaffold(body: Text('splash'))),
      GetPage(
          name: AppRoutes.home,
          page: () => const Scaffold(body: Text('main ready'))),
      GetPage(
          name: AppRoutes.login,
          page: () => const Scaffold(body: Text('login'))),
    ]));
    final logic = SplashLogic()..onInit();
    im.initializedSubject.add(true);
    im.initializedSubject.add(true);
    await tester.pump();
    expect(im.loginCalls, 1);
    im.reply.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('main ready'), findsOneWidget);
    expect(listQueries, 0);
    expect(Get.arguments['isAutoLogin'], isTrue);
    logic.onClose();
  });
}
