import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupRequestsIM extends GetxController implements IMController {
  @override
  final groupApplicationChangedSubject =
      BehaviorSubject<GroupApplicationInfo>();

  @override
  void onClose() {
    groupApplicationChangedSubject.close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GroupRequestsHome extends GetxController implements HomeLogic {
  int unreadRefreshes = 0;

  @override
  void getUnhandledGroupApplicationCount() => unreadRefreshes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupApplicationInfo request({
  String group = 'group-a',
  String user = 'applicant',
  int time = 100,
  int result = 0,
  String? handler,
  String? inviter,
}) =>
    GroupApplicationInfo(
      groupID: group,
      groupName: '$group name',
      userID: user,
      nickname: 'Applicant nickname',
      reqTime: time,
      handleResult: result,
      handleUserID: handler,
      inviterUserID: inviter,
      joinSource: inviter == null ? 3 : 2,
    );

class GroupRequestsFixture {
  static const sdk = MethodChannel('flutter_openim_sdk');
  final im = GroupRequestsIM();
  final home = GroupRequestsHome();
  final calls = <MethodCall>[];
  final recipientReplies = <Completer<String>>[];
  List<GroupApplicationInfo> recipient = [];
  List<GroupApplicationInfo> applicant = [];
  final profiles = <String, String?>{};
  bool failProfiles = false;
  bool failApplications = false;
  bool holdRecipient = false;
  PlatformException? writeError;
  void Function()? onWrite;

  List<MethodCall> callsFor(String method) =>
      calls.where((call) => call.method == method).toList();

  Future<void> initialize() async {
    Get.reset();
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current-admin',
      'imToken': 'group-test-im-token',
      'chatToken': 'group-test-chat-token',
    }));
    OpenIM.iMManager.userID = 'current-admin';
    OpenIM.iMManager.userInfo =
        UserInfo(userID: 'current-admin', nickname: 'Current administrator');
    Get.put<IMController>(im);
    Get.put<HomeLogic>(home);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getGroupApplicationListAsRecipient':
          if (failApplications) {
            throw PlatformException(code: 'NETWORK', message: 'Offline');
          }
          if (holdRecipient) {
            final reply = Completer<String>();
            recipientReplies.add(reply);
            return reply.future;
          }
          return jsonEncode(recipient.map((item) => item.toJson()).toList());
        case 'getGroupApplicationListAsApplicant':
          return jsonEncode(applicant.map((item) => item.toJson()).toList());
        case 'getJoinedGroupList':
        case 'getGroupMembersInfo':
          return '[]';
        case 'getUsersInfo':
          if (failProfiles) {
            throw PlatformException(
                code: 'NETWORK', message: 'Profile offline');
          }
          final ids = List<String>.from(call.arguments['userIDList'] as List);
          return jsonEncode([
            for (final id in ids)
              if (profiles.containsKey(id))
                {'userID': id, 'nickname': profiles[id]},
          ]);
        case 'acceptGroupApplication':
        case 'refuseGroupApplication':
          onWrite?.call();
          if (writeError != null) throw writeError!;
          return null;
        default:
          throw StateError(
              'Unexpected group application method: ${call.method}');
      }
    });
  }

  Future<GroupRequestsLogic> mount(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('zh', 'CN'),
      translations: TranslationService(),
      builder: EasyLoading.init(),
      home: const Scaffold(body: Text('group requests test')),
    ));
    final logic = Get.put(GroupRequestsLogic());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    calls.clear();
    return logic;
  }

  Future<void> refresh(WidgetTester tester, GroupRequestsLogic logic) async {
    final pending = logic.getApplicationList();
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    await pending;
  }

  Future<void> dispose() async {
    for (final reply in recipientReplies) {
      if (!reply.isCompleted) reply.complete('[]');
    }
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    await DataSp.removeLoginCertificate();
  }
}
