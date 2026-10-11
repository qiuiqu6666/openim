import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/friend_requests/process_friend_requests/process_friend_requests_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('flutter_openim_sdk');
  for (final accept in [true, false]) {
    testWidgets(
        'friend decision $accept has no global overlay or duplicate write',
        (tester) async {
      Get.testMode = true;
      SharedPreferences.setMockInitialValues({});
      await DataSp.init();
      OpenIM.iMManager.userID = 'me';
      final reply = Completer<void>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        await reply.future;
        return null;
      });
      addTearDown(() async {
        await EasyLoading.dismiss(animation: false);
        Get.reset();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(GetMaterialApp(
          builder: EasyLoading.init(), home: const Scaffold()));
      Get.to<void>(() => const Scaffold(body: Text('review')));
      await tester.pumpAndSettle();
      final logic = ProcessFriendRequestsLogic()
        ..applicationInfo = FriendApplicationInfo(
            fromUserID: 'sender', toUserID: 'me', handleResult: 0);
      final pending = accept
          ? logic.acceptFriendApplication()
          : logic.refuseFriendApplication();
      await logic.acceptFriendApplication();
      await logic.refuseFriendApplication();
      await tester.pump(const Duration(milliseconds: 10));
      expect(logic.processing.value, isTrue);
      expect(find.byType(SpinKitCircle), findsNothing);
      expect(calls,
          [accept ? 'acceptFriendApplication' : 'refuseFriendApplication']);
      reply.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(logic.processing.value, isFalse);
      expect(logic.applicationInfo.handleResult, accept ? 1 : -1);
      expect(find.text('review'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  }
}
