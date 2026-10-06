import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group/chat_group_controller.dart';

class _GroupHarness {
  _GroupHarness({
    Future<bool> Function(String)? isJoined,
    Future<List<GroupInfo>> Function(String)? groupInfo,
    Future<List<GroupMembersInfo>> Function(String, String)? selfMember,
    Future<List<GroupMembersInfo>> Function(String)? admins,
    GroupInfo? Function(String)? readCachedGroupInfo,
  }) {
    controller = ChatGroupController.withSources(
      groupID: () => groupID,
      currentUserID: () => userID,
      messages: messages,
      clearInput: () => inputCleared++,
      onGroupProfileChanged: (name, face) => profiles.add((name, face)),
      reportError: errors.add,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cached metadata is synchronous and does not replace fresh SDK roles',
      () async {
    final membership = Completer<bool>();
    final cachedReads = <String>[];
    final h = _GroupHarness(
      isJoined: (_) => membership.future,
      readCachedGroupInfo: (id) {
        cachedReads.add(id);
        return GroupInfo(
          groupID: id,
          groupName: 'Cached group',
          faceURL: 'cached-face',
          ownerUserID: 'someone-else',
          memberCount: 12,
          notification: 'Cached announcement',
          notificationUpdateTime: 41,
        );
      },
    );

    h.controller.initialize();
    h.controller.initialize();
    expect(cachedReads, ['group']);
    expect(h.controller.announcement.value, 'Cached announcement');
    expect(h.controller.announcementVersion.value, '41');
    expect(h.controller.memberCount.value, 12);
    expect(h.profiles, [('Cached group', 'cached-face')]);
    expect((h.joinedReads, h.profileReads, h.selfReads, h.adminReads),
        (0, 0, 0, 0));
    expect(h.controller.groupMembersInfo, isNull);
    expect(h.controller.ownerAndAdmin, isEmpty);
    expect(h.controller.groupMemberRoleLevel.value, GroupRoleLevel.member);
    expect(h.controller.isAdminOrOwner, isFalse);

    final pending = h.controller.loadAfterHistory();
    expect(h.joinedReads, 1);
    expect(h.controller.announcement.value, 'Cached announcement');
    membership.complete(true);
    await pending;
    expect((h.profileReads, h.selfReads, h.adminReads), (1, 1, 1));
    expect(h.controller.announcement.value, 'Announcement');
    expect(h.controller.announcementVersion.value, '42');
    expect(h.controller.memberCount.value, 5);
    expect(h.controller.isAdminOrOwner, isTrue);
    expect(h.profiles, [('Cached group', 'cached-face'), ('My group', 'face')]);
  });

  test('foreign cached metadata and changed accounts cannot seed the chat', () {
    final foreign = _GroupHarness(
      readCachedGroupInfo: (_) => GroupInfo(
          groupID: 'another-group',
          notification: 'Foreign announcement',
          memberCount: 99),
    );
    foreign.controller.initialize();
    expect(foreign.controller.groupInfo, isNull);
    expect(foreign.controller.announcement.value, isEmpty);
    expect(foreign.controller.memberCount.value, 0);
    expect(foreign.profiles, isEmpty);

    var cacheReads = 0;
    final changedAccount = _GroupHarness(readCachedGroupInfo: (id) {
      cacheReads++;
      return GroupInfo(groupID: id, notification: 'Previous account');
    });
    changedAccount.userID = 'another-account';
    changedAccount.controller.initialize();
    expect(cacheReads, 0);
    expect(changedAccount.controller.announcement.value, isEmpty);
    expect(changedAccount.profiles, isEmpty);
  });

  for (final invalidate in ['leave', 'account', 'close']) {
    test('cached chat rejects a late metadata read after $invalidate',
        () async {
      final profile = Completer<List<GroupInfo>>();
      final h = _GroupHarness(
        groupInfo: (_) => profile.future,
        readCachedGroupInfo: (id) => GroupInfo(
          groupID: id,
          groupName: 'Cached group',
          notification: 'Cached announcement',
          notificationUpdateTime: 41,
        ),
      );
      h.controller.initialize();
      final pending = h.controller.loadAfterHistory();
      await Future<void>.delayed(Duration.zero);
      expect(h.profileReads, 1);
      switch (invalidate) {
        case 'leave':
          h.left.add(GroupInfo(groupID: 'group'));
        case 'account':
          h.userID = 'another-account';
        case 'close':
          h.controller.close();
      }
      profile.complete([
        GroupInfo(
          groupID: 'group',
          groupName: 'Late group',
          notification: 'Late announcement',
          notificationUpdateTime: 99,
        ),
      ]);
      await pending;
      h.controller.initialize();
      expect(h.controller.announcement.value, 'Cached announcement');
      expect(h.controller.announcementVersion.value, '41');
      expect(h.profiles, [('Cached group', '')]);
      if (invalidate == 'leave') {
        expect(h.controller.isInvalidGroup, isTrue);
        expect(h.inputCleared, 1);
      }
    });
  }

  test('history notifications share queries and preserve group metadata',
      () async {
    final membership = Completer<bool>();
    final h = _GroupHarness(isJoined: (_) => membership.future);
    h.controller.initialize();
    h.controller.initialize();
    expect(h.joinedReads, 0);
    final first = h.controller.loadAfterHistory();
    final second = h.controller.loadAfterHistory();
    expect(second, same(first));
    expect(h.joinedReads, 1);
    membership.complete(true);
    await first;
    expect((h.profileReads, h.selfReads, h.adminReads), (1, 1, 1));
    expect(h.controller.groupInfo?.groupName, 'My group');
    expect(h.profiles, [('My group', 'face')]);
    expect(h.controller.memberCount.value, 5);
    expect(h.controller.announcement.value, 'Announcement');
    expect(h.controller.announcementVersion.value, '42');
    expect(h.controller.groupMembersInfo?.nickname, 'My name');
    expect(h.controller.isAdminOrOwner, isTrue);
    expect(h.controller.havePermissionMute, isTrue);
    expect(h.controller.memberUpdateInfoMap['me']?.nickname, 'My name');
  });

  test('closing during membership lookup cannot query or apply late state',
      () async {
    final membership = Completer<bool>();
    final h = _GroupHarness(isJoined: (_) => membership.future);
    h.controller.initialize();
    final pending = h.controller.loadAfterHistory();
    h.controller.close();
    h.controller.close();
    membership.complete(true);
    await pending;
    h.groupChanged.add(GroupInfo(groupID: 'group', groupName: 'Late'));
    expect(h.profiles, isEmpty);
    expect(h.profileReads, 0);
    expect(h.controller.isClosed, isTrue);
    expect(h.groupChanged.hasListener, isFalse);
    expect(h.changed.hasListener, isFalse);
  });

  test('leaving the group invalidates an earlier joined response', () async {
    final membership = Completer<bool>();
    final h = _GroupHarness(isJoined: (_) => membership.future);
    h.controller.initialize();
    final pending = h.controller.loadAfterHistory();
    h.left.add(GroupInfo(groupID: 'other'));
    expect(h.inputCleared, 0);
    h.deleted.add(GroupMembersInfo(groupID: 'group', userID: 'me'));
    membership.complete(true);
    await pending;
    expect(h.controller.isInGroup.value, isFalse);
    expect(h.controller.isInvalidGroup, isTrue);
    expect(h.inputCleared, 1);
    expect(h.profileReads, 0);
  });

  test('real-time profile and mute events win over older query responses',
      () async {
    final profile = Completer<List<GroupInfo>>();
    final self = Completer<List<GroupMembersInfo>>();
    final admins = Completer<List<GroupMembersInfo>>();
    final h = _GroupHarness(
        groupInfo: (_) => profile.future,
        selfMember: (_, __) => self.future,
        admins: (_) => admins.future);
    h.controller.initialize();
    final pending = h.controller.loadAfterHistory();
    await Future<void>.delayed(Duration.zero);
    h.groupChanged.add(GroupInfo(groupID: 'group', groupName: 'New name'));
    h.changed.add(GroupMembersInfo(
        groupID: 'group',
        userID: 'me',
        nickname: 'New nickname',
        roleLevel: GroupRoleLevel.admin,
        muteEndTime: h.now + 30));
    profile.complete([GroupInfo(groupID: 'group', groupName: 'Old name')]);
    self.complete([
      GroupMembersInfo(
          groupID: 'group',
          userID: 'me',
          nickname: 'Old nickname',
          roleLevel: GroupRoleLevel.member)
    ]);
    admins.complete([]);
    await pending;
    expect(h.controller.groupInfo?.groupName, 'New name');
    expect(h.controller.groupMembersInfo?.nickname, 'New nickname');
    expect(h.controller.groupMemberRoleLevel.value, GroupRoleLevel.admin);
    expect(h.controller.ownerAndAdmin.single.userID, 'me');
    expect(h.controller.sendingMuted, isTrue);
  });

  test('leaving while metadata loads cannot apply old group state', () async {
    final profile = Completer<List<GroupInfo>>();
    final h = _GroupHarness(groupInfo: (_) => profile.future);
    h.controller.initialize();
    final pending = h.controller.loadAfterHistory();
    await Future<void>.delayed(Duration.zero);
    h.left.add(GroupInfo(groupID: 'group'));
    profile.complete([GroupInfo(groupID: 'group', groupName: 'Stale')]);
    await pending;
    expect(h.controller.isInGroup.value, isFalse);
    expect(h.controller.groupInfo, isNull);
    expect(h.profiles, isEmpty);
  });

  test('an admin query merges role changes without losing other admins',
      () async {
    final admins = Completer<List<GroupMembersInfo>>();
    final h = _GroupHarness(admins: (_) => admins.future);
    h.controller.initialize();
    final pending = h.controller.loadAfterHistory();
    await Future<void>.delayed(Duration.zero);
    h.changed.add(GroupMembersInfo(
        groupID: 'group', userID: 'alice', roleLevel: GroupRoleLevel.member));
    h.changed.add(GroupMembersInfo(
        groupID: 'group',
        userID: 'new-admin',
        roleLevel: GroupRoleLevel.admin));
    admins.complete([
      GroupMembersInfo(
          groupID: 'group', userID: 'alice', roleLevel: GroupRoleLevel.admin),
      GroupMembersInfo(
          groupID: 'group', userID: 'bob', roleLevel: GroupRoleLevel.admin),
    ]);
    await pending;
    expect(h.controller.ownerAndAdmin.map((member) => member.userID),
        unorderedEquals(['bob', 'new-admin']));
  });

  test('member events update messages and survive malformed notifications',
      () async {
    final h = _GroupHarness();
    h.controller.initialize();
    final text = Message(sendID: 'alice', contentType: MessageType.text);
    final notice = Message(
        sendID: 'alice',
        contentType: 1501,
        notificationElem: NotificationElem(
            detail: jsonEncode({
          'opUser': {'userID': 'alice', 'nickname': 'Old'}
        })));
    final malformed = Message(
        sendID: 'alice',
        contentType: 1501,
        notificationElem: NotificationElem(detail: '{invalid'));
    h.messages.assignAll([text, notice, malformed]);
    h.changed.add(GroupMembersInfo(
        groupID: 'other', userID: 'alice', nickname: 'Unrelated'));
    expect(text.senderNickname, isNull);
    h.changed.add(GroupMembersInfo(
        groupID: 'group',
        userID: 'alice',
        nickname: 'Alice',
        faceURL: 'new-face',
        roleLevel: GroupRoleLevel.admin));
    expect(text.senderNickname, 'Alice');
    expect(text.senderFaceUrl, 'new-face');
    expect(jsonDecode(notice.notificationElem!.detail!)['opUser']['nickname'],
        'Alice');
    expect(h.controller.memberUpdateInfoMap['alice']?.nickname, 'Alice');
    expect(h.controller.ownerAndAdmin.single.userID, 'alice');
    expect(h.errors, hasLength(1));
    h.changed.add(GroupMembersInfo(
        groupID: 'group', userID: 'alice', roleLevel: GroupRoleLevel.member));
    expect(h.controller.ownerAndAdmin, isEmpty);
  });

  testWidgets('mute expiration refreshes reactive send permission',
      (tester) async {
    final h = _GroupHarness();
    h.controller.initialize();
    h.changed.add(GroupMembersInfo(
        groupID: 'group',
        userID: 'me',
        roleLevel: GroupRoleLevel.member,
        muteEndTime: h.now + 2));
    await tester.pumpWidget(MaterialApp(
      home: Obx(() => Text(h.controller.sendingMuted ? 'muted' : 'allowed')),
    ));
    expect(find.text('muted'), findsOneWidget);
    h.now += 3;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('allowed'), findsOneWidget);
    h.groupChanged.add(GroupInfo(groupID: 'group', status: 3));
    await tester.pump();
    expect(find.text('muted'), findsOneWidget);
    h.changed.add(GroupMembersInfo(
        groupID: 'group', userID: 'me', roleLevel: GroupRoleLevel.admin));
    await tester.pump();
    expect(find.text('allowed'), findsOneWidget);
    h.controller.close();
    await tester.pump(const Duration(minutes: 1));
  });

  test('account changes invalidate queries and failed queries can retry',
      () async {
    final membership = Completer<bool>();
    var fail = true;
    final h = _GroupHarness(isJoined: (_) {
      if (fail) {
        fail = false;
        return Future<bool>.error(StateError('temporary failure'));
      }
      return membership.future;
    });
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    expect(h.errors, hasLength(1));
    final pending = h.controller.loadAfterHistory();
    h.userID = 'new-account';
    membership.complete(true);
    await pending;
    expect(h.joinedReads, 2);
    expect(h.profileReads, 0);
    expect(h.profiles, isEmpty);
    h.groupChanged.add(GroupInfo(groupID: 'group', groupName: 'Other account'));
    h.changed.add(GroupMembersInfo(
        groupID: 'group',
        userID: 'new-account',
        roleLevel: GroupRoleLevel.admin));
    expect(h.controller.groupInfo, isNull);
    expect(h.controller.groupMembersInfo, isNull);
    await h.controller.loadAfterHistory();
    expect(h.joinedReads, 2);
  });

  test('deleted member stays non-actionable until an explicit new join', () {
    final h = _GroupHarness();
    h.controller.initialize();
    final member = GroupMembersInfo(
        groupID: 'group', userID: 'other', roleLevel: GroupRoleLevel.member);
    h.added.add(member);
    final before = h.controller.memberActionRevision;
    h.deleted.add(member);
    expect(h.controller.memberActionRevision, greaterThan(before));
    expect(h.controller.hasMemberLeft('other'), isTrue);
    expect(h.controller.memberUpdateInfoMap.containsKey('other'), isFalse);
    h.changed.add(member);
    expect(h.controller.hasMemberLeft('other'), isTrue);
    h.added.add(member);
    expect(h.controller.hasMemberLeft('other'), isFalse);
    expect(h.controller.memberUpdateInfoMap['other'], same(member));
  });

  test('avatar revision ignores unrelated groups and updates on role/profile',
      () {
    final h = _GroupHarness();
    h.controller.initialize();
    final initial = h.controller.memberActionRevision;
    h.changed.add(GroupMembersInfo(groupID: 'other', userID: 'member'));
    h.deleted.add(GroupMembersInfo(groupID: 'other', userID: 'member'));
    h.groupChanged.add(GroupInfo(groupID: 'other', status: 3));
    expect(h.controller.memberActionRevision, initial);
    h.changed.add(GroupMembersInfo(
        groupID: 'group', userID: 'member', roleLevel: GroupRoleLevel.admin));
    expect(h.controller.memberActionRevision, initial + 1);
    h.groupChanged.add(GroupInfo(groupID: 'group', status: 3));
    expect(h.controller.memberActionRevision, initial + 2);
  });
}
