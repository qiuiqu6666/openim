import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/chat_group_sources.dart';
import 'package:openim/pages/chat/messages/revocation/chat_message_revocation.dart';

import 'support/revocation_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  final calls = <MethodCall>[];
  var deny = false;

  setUp(() {
    calls.clear();
    deny = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getGroupsInfo':
          return jsonEncode([
            {'groupID': 'group', 'ownerUserID': 'owner'}
          ]);
        case 'getGroupMembersInfo':
          return jsonEncode([
            {
              'groupID': 'group',
              'userID': 'admin',
              'roleLevel': GroupRoleLevel.admin
            },
            {
              'groupID': 'group',
              'userID': 'member',
              'roleLevel': GroupRoleLevel.member
            },
          ]);
        case 'isJoinGroup':
          return 'true';
        case 'getGroupMemberOwnerAndAdmin':
          return jsonEncode(List.generate(
              25,
              (i) => {
                    'groupID': 'group',
                    'userID': 'admin-$i',
                    'roleLevel': GroupRoleLevel.admin,
                  }));
        case 'revokeMessage':
          if (deny) {
            throw PlatformException(
                code: '${SDKErrorCode.insufficientPermissions}');
          }
          return null;
        default:
          throw StateError('Unexpected SDK call ${call.method}');
      }
    });
  });
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  for (final fail in [false, true]) {
    test('default adapter uses SDK revoke, never local delete; failure=$fail',
        () async {
      deny = fail;
      final f = RevocationFixture();
      final controller = ChatMessageRevocation(
        conversationID: () => f.conversation,
        currentUserID: () => f.account,
        groupID: () => f.groupID,
        groupInfo: () => f.group,
        memberRole: (id) => id == f.account ? f.selfRole : f.senderRole,
        isJoined: () => f.joined,
        groupRevision: () => f.revision,
        isCurrentMessage: (_) => true,
        isClosed: () => false,
        onRevoked: f.removed.add,
        showFeedback: f.feedback.add,
      );
      await controller.revokeMessage(f.message());
      expect(calls.map((call) => call.method), [
        'getGroupsInfo',
        'getGroupMembersInfo',
        'isJoinGroup',
        'revokeMessage',
      ]);
      expect(calls[1].arguments['userIDList'], ['admin', 'member']);
      expect(calls.last.arguments['ManagerName'], 'messageManager');
      expect(calls.last.arguments['conversationID'], 'sg_group');
      expect(calls.last.arguments['clientMsgID'], 'message');
      expect(f.removed, fail ? isEmpty : ['message']);
      expect(f.feedback.length, fail ? 1 : 0);
    });
  }

  test('group menu roles use the unpaginated SDK owner/admin API', () async {
    final members = await ChatGroupQueries.sdk().ownerAndAdmin('group');
    expect(members, hasLength(25));
    expect(calls.single.method, 'getGroupMemberOwnerAndAdmin');
    expect(calls.single.arguments['groupID'], 'group');
    expect(calls.single.arguments.containsKey('count'), isFalse);
  });
}
