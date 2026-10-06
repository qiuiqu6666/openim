import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_source.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const previewGroupID = 'preview-group';
const previewViewer = 'im_viewer';
const _sdk = MethodChannel('flutter_openim_sdk');

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewIM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Chat extends GetxController implements ChatLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends GetxController implements ConversationLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Uses the SDK channel and IM event source used by the permission regressions.
/// Only the member HTTP transport is replaced; no backend is contacted.
class GroupPreviewFixture {
  late GroupSetupLogic setup;
  late PreviewIM im;
  final groups = <Completer<String>>[];
  final roles = <Completer<String>>[];
  final joined = <Completer<String>>[];
  final members = <Completer<Map<String, dynamic>>>[];
  final requests = <Map<String, dynamic>>[];

  Future<void> initialize({UserInfo? cachedSelfInfo}) async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await login();
    await DataSp.putServerConfig({'apiUrl': 'http://group-preview.test'});
    OpenIM.iMManager.userID = previewViewer;
    OpenIM.iMManager.userInfo = UserInfo(userID: previewViewer, nickname: '我');
    Get.put<AppController>(_App());
    im = Get.put<IMController>(PreviewIM()) as PreviewIM;
    if (cachedSelfInfo != null) im.selfInfoUpdated(cachedSelfInfo);
    Get.put<ChatLogic>(_Chat(), tag: GetTags.chat);
    Get.put<ConversationLogic>(_Conversations());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (call) {
      final reply = Completer<String>();
      switch (call.method) {
        case 'getGroupsInfo':
          groups.add(reply);
        case 'getGroupMembersInfo':
          roles.add(reply);
        case 'isJoinGroup':
          joined.add(reply);
        default:
          throw StateError('Unexpected SDK call: ${call.method}');
      }
      return reply.future;
    });
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: 'sg_preview-group',
        groupID: previewGroupID,
        conversationType: ConversationType.superGroup,
        showName: '群聊测试',
      ),
    };
    setup = Get.put(GroupSetupLogic(
      memberIdentitySource: GroupMemberIdentitySource(
        poster: (_, data, __) {
          requests.add(Map<String, dynamic>.of(data));
          final reply = Completer<Map<String, dynamic>>();
          members.add(reply);
          return reply.future;
        },
      ),
    ));
    setup.isJoinedGroup.value = true;
  }

  Future<void> close() async {
    if (!setup.isClosed) setup.onDelete();
    for (final reply in [...groups, ...roles, ...joined]) {
      if (!reply.isCompleted) reply.complete('[]');
    }
    for (final reply in members) {
      if (!reply.isCompleted) reply.complete({'members': <Object>[]});
    }
    await drainPreview();
    Get.reset();
    Get.routing.args = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  }

  Future<void> login(
      {String viewer = previewViewer, String token = 'im-token'}) async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': viewer,
      'chatToken': 'chat-token',
      'imToken': token,
    }));
  }
}

String previewGroup({int privacy = 0}) => jsonEncode([
      {
        'groupID': previewGroupID,
        'groupName': '群聊测试',
        'ownerUserID': 'im_owner',
        'memberCount': 10002,
        'lookMemberInfo': privacy,
      }
    ]);

String previewRole({int role = GroupRoleLevel.admin, int manager = 1}) =>
    jsonEncode([
      {
        'groupID': previewGroupID,
        'userID': previewViewer,
        'nickname': '我的群昵称',
        'roleLevel': role,
        'appManagerLevel': manager,
      }
    ]);

Map<String, dynamic> previewMembers({String id = 'im_peer'}) => {
      'members': [
        {
          'groupID': previewGroupID,
          'userID': id,
          'nickname': '成员一',
          'account': 'public-account',
          'roleLevel': GroupRoleLevel.member,
        }
      ],
    };

DioException previewPermanentError() {
  final request = RequestOptions(path: '/group/get_group_member_list');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response<Object>(requestOptions: request, statusCode: 403),
    error: 'Members unavailable',
  );
}

Future<void> drainPreview() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
