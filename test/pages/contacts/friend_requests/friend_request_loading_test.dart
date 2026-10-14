import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/contacts/friend_requests/friend_requests_logic.dart';
import 'package:openim/pages/contacts/request_history/data/request_list_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  @override
  final imSdkStatusPublishSubject =
      PublishSubject<({IMSdkStatus status, bool reInstall, int? progress})>();
  @override
  final friendApplicationChangedSubject =
      PublishSubject<FriendApplicationInfo>();
  @override
  void onClose() {
    imSdkStatusPublishSubject.close();
    friendApplicationChangedSubject.close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  @override
  void getUnhandledFriendApplicationCount() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const channel = MethodChannel('flutter_openim_sdk');
  late _IM im;
  late List<FriendApplicationInfo> rows;
  late List<Completer<String>> replies;
  late bool holdRecipient, holdApplicant;
  late int calls;
  final row = FriendApplicationInfo(
      fromUserID: 'other',
      toUserID: 'me',
      fromNickname: '新朋友',
      createTime: 1,
      handleResult: 0);
  setUp(() async {
    Get.reset();
    Get.testMode = true;
    RequestListCache.shared.clear();
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'me',
      'imToken': 'im',
      'chatToken': 'chat',
    }));
    OpenIM.iMManager.userID = 'me';
    im = Get.put<IMController>(_IM()) as _IM;
    Get.put<HomeLogic>(_Home());
    rows = [row];
    replies = [];
    holdRecipient = holdApplicant = false;
    calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final recipient = call.method == 'getFriendApplicationListAsRecipient';
      if (recipient) calls++;
      if (recipient ? holdRecipient : holdApplicant) {
        final reply = Completer<String>();
        replies.add(reply);
        return reply.future;
      }
      return recipient
          ? jsonEncode(rows.map((row) => row.toJson()).toList())
          : '[]';
    });
  });
  tearDown(() async {
    Get.reset();
    for (final reply in replies) {
      if (!reply.isCompleted) reply.complete('[]');
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await DataSp.removeLoginCertificate();
  });
  Future<FriendRequestsLogic> open(WidgetTester tester) async {
    final logic = Get.put(FriendRequestsLogic());
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    return logic;
  }

  testWidgets('received requests display before the outgoing read completes',
      (tester) async {
    holdApplicant = true;
    final logic = await open(tester);
    expect(logic.applicationList.single.fromNickname, '新朋友');
    expect(logic.loading.value, isTrue);
    replies.single.complete('[]');
    await tester.pumpAndSettle();
    expect(logic.loading.value, isFalse);
  });

  testWidgets('resume and sync completion refresh authoritative request state',
      (tester) async {
    final logic = await open(tester);
    rows = [];
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(logic.applicationList, isEmpty);
    rows = [row];
    im.imSdkStatusPublishSubject
        .add((status: IMSdkStatus.syncEnded, reInstall: false, progress: null));
    await tester.pumpAndSettle();
    expect(logic.applicationList.single.fromUserID, 'other');
    expect(calls, 3);
  });

  testWidgets('cache renders immediately on reopen and respects deletion',
      (tester) async {
    final logic = await open(tester);
    Get.delete<FriendRequestsLogic>(force: true);
    holdRecipient = true;
    final cached = Get.put(FriendRequestsLogic());
    expect(cached.applicationList.single.fromNickname, '新朋友');
    await cached.deleteRequest(cached.applicationList.single);
    Get.delete<FriendRequestsLogic>(force: true);
    final deleted = Get.put(FriendRequestsLogic());
    expect(deleted.applicationList, isEmpty);
    Get.delete<FriendRequestsLogic>(force: true);
    expect(logic.isClosed, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'notifications collapse to one trailing refresh and ignore stale data',
      (tester) async {
    rows = [];
    final logic = await open(tester);
    holdRecipient = true;
    final pending = logic.loadRequests();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      im.friendApplicationChangedSubject.add(row);
    }
    await tester.pump();
    expect(replies, hasLength(1));
    replies.first.complete('[]');
    await tester.pumpAndSettle();
    expect(replies, hasLength(2));
    replies.last.complete(jsonEncode([row.toJson()]));
    await tester.pumpAndSettle();
    await pending;
    expect(calls, 3); // Initial read plus two serialized refreshes.
    expect(logic.applicationList, hasLength(1));
  });
}
