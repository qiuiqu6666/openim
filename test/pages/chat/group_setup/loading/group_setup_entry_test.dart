import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:fake_async/fake_async.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim_common/openim_common.dart';

import '../members/group_preview_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupPreviewFixture fixture;
  setUp(() => fixture = GroupPreviewFixture());
  tearDown(() => fixture.close());

  GroupInfo cachedGroup() => GroupInfo(
        groupID: previewGroupID,
        groupName: '已加载的群资料',
        memberCount: 1919,
        ownerUserID: previewViewer,
        lookMemberInfo: 1,
        notification: '已加载的群公告',
      );
  GroupMembersInfo cachedMember({String user = previewViewer}) =>
      GroupMembersInfo(
        groupID: previewGroupID,
        userID: user,
        nickname: '我的群昵称',
        roleLevel: GroupRoleLevel.owner,
      );

  test('opening uses current chat data before membership query completes',
      () async {
    await fixture.initialize(
      cachedGroup: cachedGroup(),
      cachedMember: cachedMember(),
      assumeJoined: false,
    );
    final setup = fixture.setup;
    expect(setup.isJoinedGroup.value, isTrue);
    expect(setup.membership.resolved.value, isTrue);
    expect(setup.groupInfo.value.memberCount, 1919);
    expect(setup.groupInfo.value.notification, '已加载的群公告');
    expect(setup.myGroupNickname, '我的群昵称');
    expect(setup.isOwner, isTrue);
    setup.onReady();
    await drainPreview();
    // Metadata, role and member reads do not wait for the membership reply.
    expect(fixture.joined, hasLength(1));
    expect(fixture.groups, hasLength(1));
    expect(fixture.roles, hasLength(1));
    expect(fixture.members, hasLength(1));
    fixture.joined.single.complete('true');
    await drainPreview();
    expect(fixture.members, hasLength(1));
    expect(fixture.groups, hasLength(1));
    setup.groupInfo.value.groupName = 'new';
    final chat = Get.find<ChatLogic>(tag: GetTags.chat);
    expect(chat.groupInfo!.groupName, '已加载的群资料');
  });

  test('missing route arguments initializes synchronously from the chat',
      () async {
    await fixture.initialize(routeConversation: false, assumeJoined: false);
    expect(fixture.setup.conversationID, 'sg_preview-group');
    expect(fixture.setup.groupInfo.value.groupName, '群聊测试');
    expect(fixture.setup.membership.resolved.value, isFalse);
    fixture.setup.onDelete();
    expect(fixture.setup.isClosed, isTrue);
  });

  for (final scenario in [
    'unknown self',
    'other account',
    'left',
    'other group'
  ]) {
    test('$scenario does not seed membership or expose group management',
        () async {
      final group = cachedGroup();
      if (scenario == 'other group') group.groupID = 'different-group';
      await fixture.initialize(
        cachedGroup: group,
        cachedMember: scenario == 'unknown self'
            ? null
            : cachedMember(
                user: scenario == 'other account' ? 'other' : previewViewer),
        chatJoined: scenario != 'left',
        assumeJoined: false,
      );
      expect(fixture.setup.isJoinedGroup.value, isFalse);
      expect(fixture.setup.isOwnerOrAdmin, isFalse);
      expect(fixture.members, isEmpty);
    });
  }

  test('negative membership revalidation removes cached member controls',
      () async {
    await fixture.initialize(
      cachedGroup: cachedGroup(),
      cachedMember: cachedMember(),
      assumeJoined: false,
    );
    fixture.setup.onReady();
    await drainPreview();
    fixture.joined.single.complete('false');
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    fixture.joined.last.complete('false');
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isFalse);
    expect(fixture.setup.isOwnerOrAdmin, isFalse);
    expect(fixture.setup.membership.resolved.value, isTrue);
    fixture.members.single.complete(previewMembers());
    await drainPreview();
    expect(fixture.setup.memberList, isEmpty);
  });

  test('entering during SDK sync waits and recovers automatically', () async {
    await fixture.initialize(assumeJoined: false);
    fixture.im.imSdkStatus(IMSdkStatus.syncStart);
    await drainPreview();
    fixture.setup.onReady();
    await drainPreview();
    expect(fixture.joined, isEmpty);
    expect(fixture.setup.membership.resolved.value, isFalse);
    expect(fixture.setup.membership.failed.value, isFalse);
    expect(fixture.setup.groupInfo.value.groupName, '群聊测试');
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await drainPreview();
    fixture.joined.single.complete('true');
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isTrue);
    expect(fixture.members, hasLength(1));
  });

  test(
      'stalled initial sync exposes retry without trusting incomplete membership',
      () async {
    await fixture.initialize(assumeJoined: false);
    fakeAsync((time) {
      fixture.im.imSdkStatus(IMSdkStatus.syncStart);
      time.flushMicrotasks();
      fixture.setup.onReady();
      for (var i = 0; i < 4; i++) {
        time.elapse(const Duration(seconds: 5));
        fixture.im.imSdkStatus(IMSdkStatus.syncProgress);
        time.flushMicrotasks();
      }
      expect(fixture.setup.membership.failed.value, isTrue);
      expect(fixture.setup.membership.resolved.value, isFalse);
      expect(fixture.setup.isOwnerOrAdmin, isFalse);
      expect(fixture.joined, isEmpty);
      fixture.setup.refreshMembership();
      expect(fixture.setup.membership.failed.value, isFalse);
      time.elapse(const Duration(seconds: 20));
      expect(fixture.setup.membership.failed.value, isTrue);
      expect(fixture.joined, isEmpty);
      // Dispose inside the fake clock so no retry deadline escapes the test.
      fixture.setup.onDelete();
    });
  });

  test('sync supersedes an earlier membership read without erasing the page',
      () async {
    await fixture.initialize(
      cachedGroup: cachedGroup(),
      cachedMember: cachedMember(),
      assumeJoined: false,
    );
    fixture.setup.onReady();
    await drainPreview();
    fixture.im.imSdkStatus(IMSdkStatus.syncStart);
    await drainPreview();
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await drainPreview();
    expect(fixture.joined, hasLength(2));
    fixture.joined.first.complete('false');
    fixture.joined.last.complete('true');
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isTrue);
    expect(fixture.setup.isOwner, isTrue);
    expect(fixture.setup.groupInfo.value.memberCount, 1919);
  });

  for (final connection in [
    IMSdkStatus.connecting,
    IMSdkStatus.connectionFailed,
    IMSdkStatus.connectionSucceeded,
  ]) {
    test('$connection cannot make retry trust an unfinished sync cache',
        () async {
      await fixture.initialize(assumeJoined: false);
      fixture.im.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
      fixture.im.imSdkStatus(connection);
      await drainPreview();
      fixture.setup.refreshMembership();
      await drainPreview();
      expect(fixture.joined, isEmpty);
      expect(fixture.setup.membership.resolved.value, isFalse);
      fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
      await drainPreview();
      fixture.joined.single.complete('true');
      await drainPreview();
      expect(fixture.setup.isJoinedGroup.value, isTrue);
    });
  }

  test('duplicate sync completion does not restart a slow membership read',
      () async {
    await fixture.initialize(assumeJoined: false);
    fixture.im.imSdkStatus(IMSdkStatus.syncStart);
    await drainPreview();
    fixture.setup.onReady();
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await drainPreview();
    for (var i = 0; i < 7; i++) {
      fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
      await drainPreview();
    }
    expect(fixture.joined, hasLength(1));
    fixture.joined.single.complete('true');
    await drainPreview();
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await drainPreview();
    expect(fixture.joined, hasLength(1));
    expect(fixture.setup.isJoinedGroup.value, isTrue);
  });

  test('batched sync start and end supersede the old read only once', () async {
    await fixture.initialize(assumeJoined: false);
    fixture.setup.onReady();
    await drainPreview();
    fixture.im.imSdkStatus(IMSdkStatus.syncStart);
    fixture.im.imSdkStatus(IMSdkStatus.syncProgress);
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await drainPreview();
    expect(fixture.joined, hasLength(2));
    fixture.joined.first.complete('false');
    fixture.joined.last.complete('true');
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isTrue);
    expect(fixture.setup.membership.failed.value, isFalse);
  });

  for (final terminal in [IMSdkStatus.syncEnded, IMSdkStatus.syncFailed]) {
    test('batched failure and recovery respect the last phase $terminal',
        () async {
      await fixture.initialize(assumeJoined: false);
      fixture.setup.onReady();
      await drainPreview();
      fixture.im.imSdkStatus(IMSdkStatus.syncStart);
      fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
      fixture.im.imSdkStatus(IMSdkStatus.syncStart);
      fixture.im.imSdkStatus(terminal);
      await drainPreview();
      fixture.joined.first.complete('false');
      await drainPreview();
      if (terminal == IMSdkStatus.syncEnded) {
        expect(fixture.joined, hasLength(2));
        fixture.joined.last.complete('true');
        await drainPreview();
        expect(fixture.setup.isJoinedGroup.value, isTrue);
        expect(fixture.setup.membership.failed.value, isFalse);
      } else {
        expect(fixture.joined, hasLength(1));
        expect(fixture.setup.membership.resolved.value, isFalse);
        expect(fixture.setup.membership.failed.value, isTrue);
      }
    });
  }

  for (final change in ['token', 'account', 'close']) {
    test('$change rejects late membership and queued sync recovery', () async {
      await fixture.initialize(assumeJoined: false);
      fixture.setup.onReady();
      await drainPreview();
      if (change == 'token') await fixture.login(token: 'new-token');
      if (change == 'account') await fixture.login(viewer: 'new-account');
      if (change == 'close') fixture.setup.onDelete();
      fixture.im.imSdkStatus(IMSdkStatus.syncStart);
      fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
      fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
      fixture.joined.single.complete('true');
      await drainPreview();
      expect(fixture.joined, hasLength(1));
      expect(fixture.setup.isJoinedGroup.value, isFalse);
      expect(fixture.setup.membership.resolved.value, isFalse);
      expect(fixture.setup.membership.failed.value, isFalse);
      expect(fixture.groups, isEmpty);
    });
  }

  test('a new sync after completion still invalidates a pending read',
      () async {
    await fixture.initialize(assumeJoined: false);
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await drainPreview();
    fixture.im.imSdkStatus(IMSdkStatus.syncStart);
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await drainPreview();
    expect(fixture.joined, hasLength(2));
    fixture.joined.first.complete('false');
    fixture.joined.last.complete('true');
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isTrue);
  });

  test('rejoining does not restore permissions from before leaving', () async {
    await fixture.initialize(
      cachedGroup: cachedGroup(),
      cachedMember: cachedMember(),
      assumeJoined: false,
    );
    fixture.im.joinedGroupDeletedSubject.add(cachedGroup());
    await drainPreview();
    fixture.im.joinedGroupAddedSubject.add(cachedGroup());
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isTrue);
    expect(fixture.setup.isOwnerOrAdmin, isFalse);
    fixture.groups.single.complete(previewGroup());
    fixture.roles.single.complete(previewRole(role: GroupRoleLevel.member));
    await drainPreview();
    expect(fixture.setup.isOwnerOrAdmin, isFalse);
  });

  test('real leave event is not undone by sync completion or old reads',
      () async {
    await fixture.initialize(assumeJoined: false);
    fixture.setup.onReady();
    await drainPreview();
    fixture.im.joinedGroupDeletedSubject.add(cachedGroup());
    await drainPreview();
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    fixture.joined.single.complete('true');
    await drainPreview();
    expect(fixture.joined, hasLength(1));
    expect(fixture.setup.isJoinedGroup.value, isFalse);
    expect(fixture.setup.membership.resolved.value, isTrue);
    fixture.im.joinedGroupAddedSubject.add(cachedGroup());
    await drainPreview();
    expect(fixture.setup.isJoinedGroup.value, isTrue);
  });
}
