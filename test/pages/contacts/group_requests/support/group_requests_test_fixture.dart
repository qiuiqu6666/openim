import 'package:openim/pages/contacts/group_requests/data/group_notices_api.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/contacts/request_history/data/request_list_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupRequestsIM extends GetxController implements IMController {
  @override
  final imSdkStatusPublishSubject =
      PublishSubject<({IMSdkStatus status, bool reInstall, int? progress})>();
  @override
  final groupApplicationChangedSubject = PublishSubject<GroupApplicationInfo>();

  @override
  void onClose() {
    imSdkStatusPublishSubject.close();
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
  final profileReplies = <Completer<String>>[];
  final memberReplies = <Completer<String>>[];
  List<GroupApplicationInfo> recipient = [];
  List<GroupApplicationInfo> applicant = [];
  final profiles = <String, String?>{};
  bool failProfiles = false;
  bool failApplications = false;
  bool holdRecipient = false;
  bool holdProfiles = false;
  bool holdMembers = false;
  PlatformException? writeError;
  void Function()? onWrite;

  List<MethodCall> callsFor(String method) =>
      calls.where((call) => call.method == method).toList();

  Future<void> initialize() async {
    RequestListCache.shared.clear();
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
    Get.create<GroupNoticesApi>(() => GroupNoticesApi(request: _noticeRequest),
        permanent: false);
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
          return _page(recipient, call);
        case 'getGroupApplicationListAsApplicant':
          return _page(applicant, call);
        case 'getJoinedGroupList':
          return '[]';
        case 'getGroupMembersInfo':
          if (holdMembers) {
            final reply = Completer<String>();
            memberReplies.add(reply);
            return reply.future;
          }
          return '[]';
        case 'getUsersInfo':
          if (holdProfiles) {
            final reply = Completer<String>();
            profileReplies.add(reply);
            return reply.future;
          }
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

  int serverRevision = 0;
  int clearedThrough = 0;
  bool failWrites = false;
  final noticeCalls = <String>[];
  final dismissed = <String>{};
  Future<dynamic> _noticeRequest(String path, Map<String, dynamic> body) async {
    final action = Uri.parse(path).path.split('/').last;
    noticeCalls.add(action);
    if (action == 'state') {
      return {'revision': serverRevision, 'unreadCount': 0};
    }
    if (action == 'read') return {};
    if (action == 'detail') {
      final row = [...recipient, ...applicant].firstWhere((r) =>
          r.groupID == body['groupID'] &&
          r.userID == body['userID'] &&
          ((r.reqTime ?? 0) < 100000000000
                  ? (r.reqTime ?? 0) * 1000
                  : r.reqTime) ==
              body['reqTime']);
      return {
        'item': {
          ...row.toJson(),
          'handlerNickname': profiles[row.handleUserID] ?? ''
        }
      };
    }

    if (action == 'clear' || action == 'delete') {
      if (failWrites) throw StateError('server unavailable');
      if (action == 'clear') {
        final value = body['through'] as int;
        if (value > clearedThrough) clearedThrough = value;
      } else {
        dismissed
            .add('${body['groupID']}/${body['userID']}/${body['reqTime']}');
      }
      serverRevision++;
      return {};
    }
    if (failApplications) throw StateError('server unavailable');
    var rows = [...recipient, ...applicant];
    if (holdRecipient) {
      final reply = Completer<String>();
      recipientReplies.add(reply);
      rows = (jsonDecode(await reply.future) as List)
          .map((r) => GroupApplicationInfo.fromJson(
              Map<String, dynamic>.from(r as Map)))
          .toList();
    }
    int ms(GroupApplicationInfo r) =>
        (r.reqTime ?? 0) < 100000000000 ? (r.reqTime ?? 0) * 1000 : r.reqTime!;
    final cursor = body['cursor'] as String? ?? '';
    final parts = cursor.split(':');
    if (cursor.isNotEmpty && int.parse(parts[0]) != serverRevision) {
      return {'reset': true};
    }
    final offset = cursor.isEmpty ? 0 : int.parse(parts[1]);
    rows = rows
        .where((r) =>
            ms(r) > clearedThrough &&
            !dismissed.contains('${r.groupID}/${r.userID}/${ms(r)}'))
        .toList()
      ..sort((a, b) => (b.reqTime ?? 0).compareTo(a.reqTime ?? 0));
    final seen = <String>{};
    rows = rows
        .where((r) => seen.add('${r.groupID}/${r.userID}/${r.reqTime}'))
        .toList();
    return {
      'items': rows
          .skip(offset)
          .take(20)
          .map((r) => {
                ...r.toJson(),
                'handlerNickname':
                    failProfiles ? '' : profiles[r.handleUserID] ?? '',
                'inviterNickname':
                    failProfiles ? '' : profiles[r.inviterUserID] ?? '',
              })
          .toList(),
      'snapshotTime': rows.isEmpty ? 1 : ms(rows.first),
      'revision': serverRevision,
      'nextCursor':
          offset + 20 < rows.length ? '$serverRevision:${offset + 20}' : '',
    };
  }

  String _page(List<GroupApplicationInfo> items, MethodCall call) {
    final req = Map<Object?, Object?>.from(call.arguments['req'] as Map);
    final offset = req['offset'] as int;
    final count = req['count'] as int;
    return jsonEncode(
        items.skip(offset).take(count).map((item) => item.toJson()).toList());
  }

  Future<GroupRequestsLogic> mount(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('zh', 'CN'),
      translations: TranslationService(),
      builder: EasyLoading.init(),
      home: const Scaffold(body: Text('group requests test')),
    ));
    final logic = Get.put(GroupRequestsLogic(syncInterval: Duration.zero));
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
    for (final reply in [
      ...recipientReplies,
      ...profileReplies,
      ...memberReplies
    ]) {
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
