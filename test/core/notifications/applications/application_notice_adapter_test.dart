import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/notifications/applications/application_notice.dart';
import 'package:openim/core/notifications/applications/application_notice_adapter.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  const notifications =
      MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var role = GroupRoleLevel.owner;
  var handled = false;
  var muted = false;
  late int created;
  late GroupApplicationInfo group;
  late FriendApplicationInfo friend;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    Get.locale = const Locale('zh', 'CN');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.isLogined = true;
    role = GroupRoleLevel.owner;
    handled = muted = false;
    calls.clear();
    created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    group = GroupApplicationInfo(
        groupID: 'g',
        userID: 'applicant',
        reqTime: created,
        nickname: '实际申请人',
        groupName: '测试群',
        handleResult: 0,
        inviterUserID: 'inviter',
        joinSource: 2);
    friend = FriendApplicationInfo(
        fromUserID: 'applicant',
        toUserID: 'me',
        createTime: created,
        fromNickname: '小明',
        handleResult: 0);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(sdk, (call) async {
      switch (call.method) {
        case 'getGroupMembersInfo':
          return jsonEncode([
            {'groupID': 'g', 'userID': 'me', 'roleLevel': role}
          ]);
        case 'getGroupApplicationListAsRecipient':
          return jsonEncode([
            {...group.toJson(), 'handleResult': handled ? 1 : 0}
          ]);
        case 'getFriendApplicationListAsRecipient':
          return jsonEncode([
            {...friend.toJson(), 'handleResult': handled ? 1 : 0}
          ]);
        default:
          throw StateError('Unexpected SDK operation ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(notifications,
        (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(sdk, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
    debugDefaultTargetPlatformOverride = null;
    OpenIM.iMManager.isLogined = false;
    Get.reset();
  });
  create() => createApplicationNotices(
      plugin: FlutterLocalNotificationsPlugin(),
      session: () => (accountID: 'me', sessionKey: 'session'),
      ready: () => true,
      foreground: () => true,
      globalReceiveOption: () => muted ? 2 : 0,
      suppressSound: () => false)
    ..synchronize();
  Map args() => calls.singleWhere((c) => c.method == 'show').arguments as Map;

  for (final privileged in [GroupRoleLevel.owner, GroupRoleLevel.admin]) {
    test('group role $privileged uses actual applicant and group name',
        () async {
      role = privileged;
      final runtime = create();
      await runtime.receive(ApplicationNotice.group(group));
      expect(args()['title'], '新的加群申请');
      expect(args()['body'], '实际申请人申请加入「测试群」，请审核');
      expect(args()['payload'], contains('local_application'));
      runtime.close();
    });
  }
  test('ordinary member and handled application do not show approval alerts',
      () async {
    role = 20;
    var runtime = create();
    await runtime.receive(ApplicationNotice.group(group));
    runtime.close();
    expect(calls, isEmpty);
    role = GroupRoleLevel.owner;
    handled = true;
    runtime = create();
    await runtime.receive(ApplicationNotice.group(group));
    runtime.close();
    expect(calls, isEmpty);
  });
  test(
      'friend notification uses authoritative nickname and respects global DND',
      () async {
    var runtime = create();
    await runtime.receive(ApplicationNotice.friend(friend));
    runtime.close();
    expect(args()['title'], '新的好友申请');
    expect(args()['body'], '小明申请添加你为好友');
    calls.clear();
    muted = true;
    friend.fromUserID = 'new-applicant';
    runtime = create();
    await runtime.receive(ApplicationNotice.friend(friend));
    runtime.close();
    expect(calls, isEmpty);
  });
  test('empty names use server-compatible fallback wording', () async {
    group.nickname = '';
    group.groupName = '';
    final runtime = create();
    await runtime.receive(ApplicationNotice.group(group));
    runtime.close();
    expect(args()['body'], '有人申请加入「群聊」，请审核');
  });
}
