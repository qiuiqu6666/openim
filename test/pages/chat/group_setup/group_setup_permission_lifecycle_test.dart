import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_info.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_source.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_manage_logic.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sdk = MethodChannel('flutter_openim_sdk');
const _groupID = 'group';
const _self = 'im_me';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
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

Future<void> _login({String account = _self, String token = 'im-token'}) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': account,
    'chatToken': 'chat-token',
    'imToken': token,
  }));
}

String _group({
  String id = _groupID,
  String owner = 'im_owner',
  int look = 0,
}) =>
    jsonEncode([
      {
        'groupID': id,
        'groupName': 'Group',
        'ownerUserID': owner,
        'lookMemberInfo': look,
      }
    ]);

String _role({
  String groupID = _groupID,
  String userID = _self,
  int role = GroupRoleLevel.admin,
  int appManager = 1,
}) =>
    jsonEncode([
      {
        'groupID': groupID,
        'userID': userID,
        'nickname': 'SDK name',
        'roleLevel': role,
        'appManagerLevel': appManager,
      }
    ]);

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupSetupLogic setup;
  late _IM im;
  late List<Completer<String>> groupReplies;
  late List<Completer<String>> roleReplies;
  late List<Completer<String>> writeReplies;
  late List<Completer<String>> joinedReplies;
  late List<Completer<Map<String, dynamic>>> identityReplies;
  late List<MethodCall> nativeCalls;
  var gateIdentities = false;
  GroupManageLogic? manage;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _login();
    await DataSp.putServerConfig({'apiUrl': 'http://groups.test'});
    OpenIM.iMManager.userID = _self;
    OpenIM.iMManager.userInfo = UserInfo(userID: _self, nickname: 'Me');
    Get.put<AppController>(_App());
    im = Get.put<IMController>(_IM()) as _IM;
    Get.put<ChatLogic>(_Chat(), tag: GetTags.chat);
    Get.put<ConversationLogic>(_Conversations());
    groupReplies = [];
    roleReplies = [];
    writeReplies = [];
    joinedReplies = [];
    identityReplies = [];
    nativeCalls = [];
    gateIdentities = false;
    manage = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (call) {
      nativeCalls.add(call);
      final reply = Completer<String>();
      switch (call.method) {
        case 'getGroupsInfo':
          groupReplies.add(reply);
        case 'getGroupMembersInfo':
          roleReplies.add(reply);
        case 'setGroupInfo':
        case 'changeGroupMute':
          writeReplies.add(reply);
        case 'isJoinGroup':
          joinedReplies.add(reply);
        default:
          throw StateError('Unexpected native group call: ${call.method}');
      }
      return reply.future;
    });
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: 'sg_group',
        groupID: _groupID,
        conversationType: ConversationType.superGroup,
        showName: 'Group',
      ),
    };
    setup = Get.put(GroupSetupLogic(
      memberIdentitySource: GroupMemberIdentitySource(
        poster: (_, __, ___) async {
          if (gateIdentities) {
            final reply = Completer<Map<String, dynamic>>();
            identityReplies.add(reply);
            return reply.future;
          }
          return {'members': <Object>[]};
        },
      ),
    ));
    setup.isJoinedGroup.value = true;
  });

  tearDown(() async {
    if (manage != null && !manage!.isClosed) manage!.onDelete();
    if (!setup.isClosed) setup.onDelete();
    for (final reply in [
      ...groupReplies,
      ...roleReplies,
      ...writeReplies,
      ...joinedReplies,
    ]) {
      if (!reply.isCompleted) reply.complete('[]');
    }
    for (final reply in identityReplies) {
      if (!reply.isCompleted) reply.complete({'members': <Object>[]});
    }
    await _drain();
    Get.reset();
    Get.routing.args = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  });

  test('an older role reply cannot restore admin after a demotion event',
      () async {
    setup.myGroupMembersInfo.value.roleLevel = GroupRoleLevel.admin;
    final pending = setup.getMyGroupMemberInfo();
    await _drain();
    im.groupMemberInfoChanged(GroupMembersInfo(
      groupID: _groupID,
      userID: _self,
      roleLevel: GroupRoleLevel.member,
      appManagerLevel: 0,
    ));
    await _drain();
    roleReplies.single.complete(_role());
    await pending;
    expect(setup.myGroupMembersInfo.value.roleLevel, GroupRoleLevel.member);
    expect(setup.myGroupMembersInfo.value.appManagerLevel, 0);
    expect(setup.isOwnerOrAdmin, isFalse);
  });

  test('an app manager change invalidates an older same-role reply', () async {
    setup.myGroupMembersInfo.value
      ..roleLevel = GroupRoleLevel.member
      ..appManagerLevel = 1;
    final pending = setup.getMyGroupMemberInfo();
    await _drain();
    im.groupMemberInfoChanged(GroupMembersInfo(
      groupID: _groupID,
      userID: _self,
      roleLevel: GroupRoleLevel.member,
      appManagerLevel: 0,
    ));
    await _drain();
    roleReplies.single.complete(_role(role: GroupRoleLevel.member));
    await pending;
    expect(setup.myGroupMembersInfo.value.appManagerLevel, 0);
  });

  test('an older group reply cannot restore privacy before the latest event',
      () async {
    final pending = setup.getGroupInfo();
    await _drain();
    im.groupInfoChanged(GroupInfo(groupID: _groupID, lookMemberInfo: 1));
    await _drain();
    groupReplies.single.complete(_group(look: 0));
    await pending;
    expect(setup.groupInfo.value.lookMemberInfo, 1);
  });

  test('initial group and role reads can both initialize concurrently',
      () async {
    final groupPending = setup.getGroupInfo();
    final rolePending = setup.getMyGroupMemberInfo();
    await _drain();
    groupReplies.single.complete(_group(look: 1));
    await groupPending;
    roleReplies.single.complete(_role());
    await rolePending;
    expect(setup.groupInfo.value.lookMemberInfo, 1);
    expect(setup.myGroupMembersInfo.value.roleLevel, GroupRoleLevel.admin);
    expect(setup.myGroupMembersInfo.value.appManagerLevel, 1);
    expect(roleReplies, hasLength(1));
  });

  test('only the latest role and group query may apply in a permission epoch',
      () async {
    final oldGroup = setup.getGroupInfo();
    final oldRole = setup.getMyGroupMemberInfo();
    final currentGroup = setup.getGroupInfo();
    final currentRole = setup.getMyGroupMemberInfo();
    await _drain();
    groupReplies.last.complete(_group(look: 1));
    roleReplies.last
        .complete(_role(role: GroupRoleLevel.member, appManager: 0));
    await Future.wait([currentGroup, currentRole]);
    groupReplies.first.complete(_group(look: 0));
    roleReplies.first.complete(_role());
    await Future.wait([oldGroup, oldRole]);
    expect(setup.groupInfo.value.lookMemberInfo, 1);
    expect(setup.myGroupMembersInfo.value.roleLevel, GroupRoleLevel.member);
  });

  test('a privacy event replaces the canceled initial role read', () async {
    final pending = setup.getMyGroupMemberInfo();
    await _drain();
    im.groupInfoChanged(GroupInfo(groupID: _groupID, lookMemberInfo: 1));
    await _drain();
    expect(roleReplies, hasLength(2));
    roleReplies.last
        .complete(_role(role: GroupRoleLevel.member, appManager: 0));
    await _drain();
    roleReplies.first.complete(_role());
    await pending;
    expect(setup.myGroupMembersInfo.value.roleLevel, GroupRoleLevel.member);
    expect(setup.myGroupMembersInfo.value.appManagerLevel, 0);
    expect(setup.groupInfo.value.lookMemberInfo, 1);
  });

  for (final state in ['active', 'left', 'closed']) {
    test('optional SDK metadata failures are contained when $state', () async {
      setup.myGroupMembersInfo.value.roleLevel = GroupRoleLevel.member;
      final groupPending = setup.getGroupInfo();
      final rolePending = setup.getMyGroupMemberInfo();
      await _drain();
      if (state == 'left') {
        im.joinedGroupDeleted(GroupInfo(groupID: _groupID));
        await _drain();
      } else if (state == 'closed') {
        setup.onDelete();
      }
      groupReplies.single.completeError(
          PlatformException(code: '500', message: 'SDK metadata unavailable'));
      roleReplies.single.completeError(
          PlatformException(code: '500', message: 'SDK role unavailable'));
      await Future.wait([groupPending, rolePending]);
      expect(setup.myGroupMembersInfo.value.roleLevel, GroupRoleLevel.member);
      expect(setup.groupInfo.value.lookMemberInfo, isNull);
    });
  }

  test('SDK group and member payloads must belong to this group and viewer',
      () async {
    final groupPending = setup.getGroupInfo();
    final rolePending = setup.getMyGroupMemberInfo();
    await _drain();
    groupReplies.single.complete(_group(id: 'another-group'));
    roleReplies.single.complete(_role(userID: 'im_peer'));
    await Future.wait([groupPending, rolePending]);
    expect(setup.groupInfo.value.groupID, _groupID);
    expect(setup.groupInfo.value.lookMemberInfo, isNull);
    expect(setup.myGroupMembersInfo.value.userID, _self);
    expect(setup.myGroupMembersInfo.value.roleLevel, isNull);
    final wrongGroupRole = setup.getMyGroupMemberInfo();
    await _drain();
    roleReplies.last.complete(_role(groupID: 'another-group'));
    await wrongGroupRole;
    expect(setup.myGroupMembersInfo.value.roleLevel, isNull);
  });

  for (final change in [
    'account',
    'sdk account',
    'IM token',
    'server',
    'group'
  ]) {
    test('$change changes discard both earlier SDK permission reads', () async {
      final groupPending = setup.getGroupInfo();
      final rolePending = setup.getMyGroupMemberInfo();
      await _drain();
      switch (change) {
        case 'account':
          await _login(account: 'im_next');
        case 'sdk account':
          OpenIM.iMManager.userID = 'im_next';
        case 'IM token':
          await _login(token: 'rotated-im-token');
        case 'server':
          await DataSp.putServerConfig({'apiUrl': 'http://other-groups.test'});
        case 'group':
          setup.groupInfo.value = GroupInfo(groupID: 'another-group');
      }
      groupReplies.single.complete(_group(look: 1));
      roleReplies.single.complete(_role());
      await Future.wait([groupPending, rolePending]);
      expect(setup.groupInfo.value.lookMemberInfo, isNull);
      expect(setup.myGroupMembersInfo.value.roleLevel, isNull);
      final count = nativeCalls.length;
      await setup.getMyGroupMemberInfo();
      await setup.getGroupInfo();
      expect(nativeCalls, hasLength(count));
    });
  }

  for (final leave in [
    'joined group deletion',
    'self member deletion',
    'close'
  ]) {
    test('$leave clears accounts and discards older permission reads',
        () async {
      setup.memberList.add(GroupMemberIdentityInfo(
        groupID: _groupID,
        userID: 'im_peer',
        account: 'a123456789',
      ));
      final groupPending = setup.getGroupInfo();
      final rolePending = setup.getMyGroupMemberInfo();
      await _drain();
      switch (leave) {
        case 'joined group deletion':
          im.joinedGroupDeleted(GroupInfo(groupID: _groupID));
        case 'self member deletion':
          im.groupMemberDeleted(GroupMembersInfo(
            groupID: _groupID,
            userID: _self,
          ));
        case 'close':
          setup.onDelete();
      }
      await _drain();
      expect(setup.memberList, isEmpty);
      groupReplies.single.complete(_group(look: 1));
      roleReplies.single.complete(_role());
      await Future.wait([groupPending, rolePending]);
      expect(setup.groupInfo.value.lookMemberInfo, isNull);
      expect(setup.myGroupMembersInfo.value.roleLevel, isNull);
    });
  }

  test('an older joined check cannot revive membership after a leave event',
      () async {
    setup.onReady();
    await _drain();
    im.joinedGroupDeleted(GroupInfo(groupID: _groupID));
    await _drain();
    joinedReplies.single.complete('true');
    await _drain();
    expect(setup.isJoinedGroup.value, isFalse);
    expect(groupReplies, isEmpty);
    expect(roleReplies, isEmpty);
  });

  test(
      'demotion clears accounts and prevents an older member page restoring them',
      () async {
    gateIdentities = true;
    setup.myGroupMembersInfo.value.roleLevel = GroupRoleLevel.admin;
    setup.memberList.add(GroupMemberIdentityInfo(
      groupID: _groupID,
      userID: 'im_peer',
      account: 'a123456789',
    ));
    final pending = setup.getGroupMembers();
    await _drain();
    im.groupMemberInfoChanged(GroupMembersInfo(
      groupID: _groupID,
      userID: _self,
      roleLevel: GroupRoleLevel.member,
    ));
    await _drain();
    expect(setup.memberList, isEmpty);
    expect(identityReplies, hasLength(2));
    identityReplies.first.complete({
      'members': [
        {'groupID': _groupID, 'userID': 'im_peer', 'account': 'a123456789'}
      ]
    });
    await pending;
    expect(setup.memberList, isEmpty);
    identityReplies.last.complete({
      'members': [
        {
          'groupID': _groupID,
          'userID': 'im_peer',
          'account': 'long-mapped-account'
        }
      ]
    });
    await _drain();
    expect((setup.memberList.single as GroupMemberIdentityInfo).account,
        'long-mapped-account');
    expect(setup.memberList.single.userID, 'im_peer');
  });

  GroupManageLogic openManage() {
    setup.groupInfo.value.ownerUserID = _self;
    setup.myGroupMembersInfo.value.roleLevel = GroupRoleLevel.owner;
    return manage = GroupManageLogic();
  }

  Future<void> completeWrite() async {
    await _drain();
    writeReplies.single.complete('');
    await _drain();
  }

  test('saving rules only applies and broadcasts the requested group',
      () async {
    final broadcasts = <GroupInfo>[];
    final subscription = im.groupInfoUpdatedSubject.listen(broadcasts.add);
    addTearDown(subscription.cancel);
    final pending = openManage().saveRules(look: 1);
    await completeWrite();
    groupReplies.single.complete(_group(owner: _self, look: 1));
    await pending;
    await _drain();
    expect(setup.groupInfo.value.lookMemberInfo, 1);
    expect(broadcasts.map((group) => group.groupID), [_groupID]);
    expect(manage!.busy.value, isFalse);
    expect(nativeCalls.first.arguments['groupInfo']['groupID'], _groupID);
  });

  test('saving rules ignores a response belonging to another group', () async {
    final broadcasts = <GroupInfo>[];
    final subscription = im.groupInfoUpdatedSubject.listen(broadcasts.add);
    addTearDown(subscription.cancel);
    final pending = openManage().saveRules(look: 1);
    await completeWrite();
    groupReplies.single.complete(_group(id: 'another-group', look: 1));
    await pending;
    await _drain();
    expect(setup.groupInfo.value.lookMemberInfo, isNull);
    expect(broadcasts, isEmpty);
  });

  test('a newer privacy event wins over the save reconciliation read',
      () async {
    final broadcasts = <GroupInfo>[];
    final subscription = im.groupInfoUpdatedSubject.listen(broadcasts.add);
    addTearDown(subscription.cancel);
    final pending = openManage().saveRules(look: 0);
    await completeWrite();
    im.groupInfoChanged(GroupInfo(
      groupID: _groupID,
      ownerUserID: _self,
      lookMemberInfo: 1,
    ));
    await _drain();
    groupReplies.single.complete(_group(owner: _self, look: 0));
    await pending;
    await _drain();
    expect(setup.groupInfo.value.lookMemberInfo, 1);
    expect(broadcasts, hasLength(1));
    expect(broadcasts.single.lookMemberInfo, 1);
  });

  for (final change in ['leave', 'setup close', 'manage close', 'IM token']) {
    test('$change during a write skips stale rule reconciliation and broadcast',
        () async {
      final broadcasts = <GroupInfo>[];
      final subscription = im.groupInfoUpdatedSubject.listen(broadcasts.add);
      addTearDown(subscription.cancel);
      final pending = openManage().saveRules(look: 1);
      await _drain();
      switch (change) {
        case 'leave':
          im.joinedGroupDeleted(GroupInfo(groupID: _groupID));
        case 'setup close':
          setup.onDelete();
        case 'manage close':
          manage!.onDelete();
        case 'IM token':
          await _login(token: 'rotated-im-token');
      }
      await _drain();
      writeReplies.single.complete('');
      await pending;
      expect(groupReplies, isEmpty);
      expect(broadcasts, isEmpty);
      expect(setup.groupInfo.value.lookMemberInfo, isNull);
    });
  }
}
