import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group/chat_group_controller.dart';

class ChatGroupHarness {
  ChatGroupHarness({
    Future<bool> Function(String)? isJoined,
    Future<bool> Function(String, String)? verifyMembership,
    Future<List<GroupInfo>> Function(String)? groupInfo,
    Future<List<GroupMembersInfo>> Function(String, String)? selfMember,
    Future<List<GroupMembersInfo>> Function(String)? admins,
    Future<List<GroupMembersInfo>> Function(String, List<String>)? members,
    GroupInfo? Function(String)? readCachedGroupInfo,
    Duration queryTimeout = const Duration(seconds: 15),
  }) {
    controller = ChatGroupController.withSources(
      groupID: () => groupID,
      currentUserID: () => userID,
      messages: messages,
      clearInput: () => inputCleared++,
      onGroupProfileChanged: (name, face) => profiles.add((name, face)),
      reportError: errors.add,
      queryTimeout: queryTimeout,
      nowSeconds: () => now,
      readCachedGroupInfo: readCachedGroupInfo,
      events: ChatGroupEvents(
        joined: joined.stream,
        left: left.stream,
        memberAdded: added.stream,
        memberDeleted: deleted.stream,
        memberChanged: changed.stream,
        groupChanged: groupChanged.stream,
      ),
      queries: ChatGroupQueries(
        members: members,
        verifyMembership: verifyMembership,
        isJoined: (id) {
          joinedReads++;
          return isJoined?.call(id) ?? Future.value(true);
        },
        groupInfo: (id) {
          profileReads++;
          return groupInfo?.call(id) ??
              Future.value([
                GroupInfo(
                    groupID: id,
                    groupName: 'My group',
                    faceURL: 'face',
                    ownerUserID: 'me',
                    memberCount: 5,
                    notification: 'Announcement',
                    notificationUpdateTime: 42)
              ]);
        },
        selfMember: (id, user) {
          selfReads++;
          return selfMember?.call(id, user) ??
              Future.value([
                GroupMembersInfo(
                    groupID: id,
                    userID: user,
                    nickname: 'My name',
                    roleLevel: GroupRoleLevel.owner)
              ]);
        },
        ownerAndAdmin: (id) {
          adminReads++;
          return admins?.call(id) ??
              Future.value([
                GroupMembersInfo(
                    groupID: id, userID: 'me', roleLevel: GroupRoleLevel.owner)
              ]);
        },
      ),
    );
    addTearDown(close);
  }

  final joined = StreamController<GroupInfo>.broadcast(sync: true);
  final left = StreamController<GroupInfo>.broadcast(sync: true);
  final added = StreamController<GroupMembersInfo>.broadcast(sync: true);
  final deleted = StreamController<GroupMembersInfo>.broadcast(sync: true);
  final changed = StreamController<GroupMembersInfo>.broadcast(sync: true);
  final groupChanged = StreamController<GroupInfo>.broadcast(sync: true);
  final messages = <Message>[].obs;
  final profiles = <(String, String)>[];
  final errors = <Object>[];
  int inputCleared = 0;
  int joinedReads = 0, profileReads = 0, selfReads = 0, adminReads = 0;
  int now = 1000;
  String? groupID = 'group';
  String userID = 'me';
  late final ChatGroupController controller;

  Future<void> close() async {
    controller.close();
    await Future.wait([
      joined.close(),
      left.close(),
      added.close(),
      deleted.close(),
      changed.close(),
      groupChanged.close(),
    ]);
  }
}
