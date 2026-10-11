import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void onClose() {
    close();
    super.onClose();
  }
}

class _Push extends GetxController implements PushController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache extends GetxController implements CacheController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BadgeHome extends HomeLogic {
  @override
  void onReady() {} // Exclude unrelated call history/platform entry work.
}

void main() {
  const channel = MethodChannel('flutter_openim_sdk');
  late _IM im;
  late _BadgeHome home;
  late Map<String, List<Completer<String>>> requests;
  final friend = FriendApplicationInfo(
      fromUserID: 'friend', toUserID: 'me', createTime: 1, handleResult: 0);
  final group = GroupApplicationInfo(
      groupID: 'group', userID: 'friend', reqTime: 1, handleResult: 0);
  setUp(() async {
    Get.reset();
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'me',
      'chatToken': 'chat',
      'imToken': 'im',
    }));
    OpenIM.iMManager.userID = 'me';
    Get.put<AppController>(_App());
    im = Get.put<IMController>(_IM()) as _IM;
    Get.put<PushController>(_Push());
    Get.put<CacheController>(_Cache());
    requests = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final reply = Completer<String>();
      requests.putIfAbsent(call.method, () => []).add(reply);
      return reply.future;
    });
    home = _BadgeHome();
  });
  tearDown(() async {
    home.onDelete();
    for (final calls in requests.values) {
      for (final reply in calls) {
        if (!reply.isCompleted) reply.complete('[]');
      }
    }
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await DataSp.removeLoginCertificate();
  });

  testWidgets('SDK event bursts issue one query per badge and retain counts',
      (tester) async {
    home.onInit();
    for (var i = 0; i < 10; i++) {
      im.friendApplicationAdded(friend);
      im.groupApplicationAdded(group);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(requests.keys.toSet(), {
      'getFriendApplicationListAsRecipient',
      'getGroupApplicationListAsRecipient',
    });
    expect(requests.values.every((calls) => calls.length == 1), isTrue);
    requests['getFriendApplicationListAsRecipient']!
        .single
        .complete(jsonEncode([friend.toJson()]));
    requests['getGroupApplicationListAsRecipient']!
        .single
        .complete(jsonEncode([group.toJson()]));
    await tester.pump();
    expect(home.unhandledFriendApplicationCount.value, 1);
    expect(home.unhandledGroupApplicationCount.value, 1);
    expect(home.unhandledCount.value, 2);
  });

  testWidgets('late replies cannot update a closed home or a renewed token',
      (tester) async {
    home.onInit();
    home.getUnhandledFriendApplicationCount();
    home.getUnhandledGroupApplicationCount();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
        () async => await DataSp.putLoginCertificate(LoginCertificate.fromJson({
              'userID': 'me',
              'chatToken': 'renewed',
              'imToken': 'im',
            })));
    requests['getFriendApplicationListAsRecipient']!
        .single
        .complete(jsonEncode([friend.toJson()]));
    await tester.pump();
    expect(home.unhandledFriendApplicationCount.value, 0);
    home.onDelete();
    requests['getGroupApplicationListAsRecipient']!
        .single
        .complete(jsonEncode([group.toJson()]));
    await tester.pump();
    expect(home.unhandledGroupApplicationCount.value, 0);
    home.getUnhandledGroupApplicationCount();
    await tester.pump(const Duration(seconds: 1));
    expect(requests['getGroupApplicationListAsRecipient'], hasLength(1));
  });
}
