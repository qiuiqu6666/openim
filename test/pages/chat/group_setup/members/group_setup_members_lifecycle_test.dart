import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_info.dart';
import 'package:openim_common/openim_common.dart';

import 'group_preview_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupPreviewFixture fixture;

  setUp(() async {
    fixture = GroupPreviewFixture();
    await fixture.initialize();
  });

  tearDown(() => fixture.close());

  for (final memberFirst in [true, false]) {
    test(
        'initial group, role and member reads keep the preview when members '
        'finish ${memberFirst ? 'first' : 'last'}', () async {
      final setup = fixture.setup;
      final group = setup.getGroupInfo();
      final role = setup.getMyGroupMemberInfo();
      final members = setup.getGroupMembers();
      await drainPreview();
      expect(fixture.members, hasLength(1));
      expect(setup.membersLoading.value, isTrue);
      if (memberFirst) {
        fixture.members.single.complete(previewMembers());
        await members;
        expect(setup.memberList.single.userID, 'im_peer');
      }
      fixture.groups.single.complete(previewGroup());
      fixture.roles.single.complete(previewRole());
      await Future.wait([group, role]);
      await drainPreview();
      expect(fixture.members, hasLength(1));
      if (!memberFirst) {
        expect(setup.membersLoading.value, isTrue);
        fixture.members.single.complete(previewMembers());
        await members;
      }
      expect(setup.groupInfo.value.memberCount, 10002);
      expect(setup.memberList.single.userID, 'im_peer');
      expect(setup.membersLoading.value, isFalse);
      expect(setup.membersFailed.value, isFalse);
      expect(fixture.requests.single['pagination'], {
        'pageNumber': 1,
        'showNumber': 20,
      });
    });
  }

  test('repeated retry taps share the same in-flight member request', () async {
    final setup = fixture.setup;
    final first = setup.getGroupMembers();
    final second = setup.getGroupMembers();
    final third = setup.getGroupMembers();
    await drainPreview();
    expect(fixture.members, hasLength(1));
    fixture.members.single.complete(previewMembers());
    await Future.wait([first, second, third]);
    expect(setup.memberList.single.userID, 'im_peer');
    expect(setup.membersLoading.value, isFalse);
    expect(setup.membersFailed.value, isFalse);
  });

  test('a member failure is explicit and retry restores the preview', () async {
    final setup = fixture.setup;
    final first = setup.getGroupMembers();
    await drainPreview();
    fixture.members.single.completeError(previewPermanentError());
    await first;
    expect(setup.memberList, isEmpty);
    expect(setup.membersLoading.value, isFalse);
    expect(setup.membersFailed.value, isTrue);
    final retry = setup.getGroupMembers();
    await drainPreview();
    expect(setup.membersLoading.value, isTrue);
    expect(setup.membersFailed.value, isFalse);
    fixture.members.last.complete(previewMembers());
    await retry;
    expect(setup.memberList.single.userID, 'im_peer');
    expect(setup.membersFailed.value, isFalse);
  });

  test('an ordinary failed refresh preserves the last successful member rows',
      () async {
    final setup = fixture.setup;
    final first = setup.getGroupMembers();
    await drainPreview();
    fixture.members.single.complete(previewMembers());
    await first;
    final refresh = setup.getGroupMembers();
    await drainPreview();
    expect(setup.memberList.single.userID, 'im_peer');
    fixture.members.last.completeError(previewPermanentError());
    await refresh;
    expect(setup.memberList.single.userID, 'im_peer');
    expect(setup.membersLoading.value, isFalse);
    expect(setup.membersFailed.value, isTrue);
  });

  test('demotion discards an old member page without ending the new loading',
      () async {
    final setup = fixture.setup;
    setup.myGroupMembersInfo.value
      ..roleLevel = GroupRoleLevel.admin
      ..appManagerLevel = 1;
    final old = setup.getGroupMembers();
    await drainPreview();
    fixture.im.groupMemberInfoChanged(GroupMembersInfo(
      groupID: previewGroupID,
      userID: previewViewer,
      roleLevel: GroupRoleLevel.member,
      appManagerLevel: 0,
    ));
    await drainPreview();
    expect(fixture.members, hasLength(2));
    expect(setup.memberList, isEmpty);
    fixture.members.first.complete(previewMembers(id: 'old-peer'));
    await old;
    expect(setup.memberList, isEmpty);
    expect(setup.membersLoading.value, isTrue);
    fixture.members.last.completeError(previewPermanentError());
    await drainPreview();
    expect(setup.membersLoading.value, isFalse);
    expect(setup.membersFailed.value, isTrue);
    expect(setup.memberList, isEmpty);
  });

  test('a late old page cannot replace the replacement page error', () async {
    final setup = fixture.setup;
    setup.myGroupMembersInfo.value.roleLevel = GroupRoleLevel.admin;
    final old = setup.getGroupMembers();
    await drainPreview();
    fixture.im.groupMemberInfoChanged(GroupMembersInfo(
      groupID: previewGroupID,
      userID: previewViewer,
      roleLevel: GroupRoleLevel.member,
    ));
    await drainPreview();
    fixture.members.last.completeError(previewPermanentError());
    await drainPreview();
    expect(setup.membersFailed.value, isTrue);
    fixture.members.first.complete(previewMembers());
    await old;
    expect(setup.membersFailed.value, isTrue);
    expect(setup.membersLoading.value, isFalse);
    expect(setup.memberList, isEmpty);
  });

  test('self profile event rechecks accounts when the group role stays equal',
      () async {
    final setup = fixture.setup;
    setup.myGroupMembersInfo.value
      ..roleLevel = GroupRoleLevel.member
      ..appManagerLevel = 0;
    final first = setup.getGroupMembers();
    await drainPreview();
    fixture.members.single.complete(previewMembers());
    await first;
    final old = setup.getGroupMembers();
    await drainPreview();
    fixture.im.selfInfoUpdated(UserInfo(userID: 'another-viewer'));
    await drainPreview();
    expect(fixture.members, hasLength(2));
    expect(setup.memberList, hasLength(1));

    fixture.im
        .selfInfoUpdated(UserInfo(userID: previewViewer, appMangerLevel: 1));
    await drainPreview();
    expect(setup.myGroupMembersInfo.value.roleLevel, GroupRoleLevel.member);
    expect(setup.memberList, isEmpty);
    expect(fixture.members, hasLength(3));
    expect(fixture.requests.last['pagination'], {
      'pageNumber': 1,
      'showNumber': 20,
    });
    fixture.groups.single.complete(previewGroup(privacy: 1));
    fixture.roles.single
        .complete(previewRole(role: GroupRoleLevel.member, manager: 0));
    await drainPreview();
    expect(fixture.members, hasLength(3));
    fixture.members[1].complete(previewMembers(id: 'old-peer'));
    await old;
    expect(setup.memberList, isEmpty);
    final current = previewMembers();
    (current['members'] as List).single.remove('account');
    fixture.members.last.complete(current);
    await drainPreview();
    expect(
        (setup.memberList.single as GroupMemberIdentityInfo).account, isNull);

    setup.onDelete();
    expect(fixture.im.selfInfoUpdatedSubject.hasListener, isFalse);
    fixture.im.selfInfoUpdated(UserInfo(userID: previewViewer));
    await drainPreview();
    expect(fixture.members, hasLength(3));
  });

  test('cached self profile replay does not start an extra preview request',
      () async {
    await fixture.close();
    fixture = GroupPreviewFixture();
    await fixture.initialize(
        cachedSelfInfo: UserInfo(userID: previewViewer, appMangerLevel: 2));
    await drainPreview();
    expect(fixture.members, isEmpty);
    final first = fixture.setup.getGroupMembers();
    await drainPreview();
    expect(fixture.members, hasLength(1));
    fixture.members.single.complete(previewMembers());
    await first;
    expect(fixture.members, hasLength(1));
  });

  for (final membersFirst in [true, false]) {
    test(
        'self profile event replaces unfinished initial metadata when members '
        'finish ${membersFirst ? 'first' : 'last'}', () async {
      final setup = fixture.setup;
      final oldGroup = setup.getGroupInfo();
      final oldRole = setup.getMyGroupMemberInfo();
      final oldMembers = setup.getGroupMembers();
      await drainPreview();
      fixture.im.selfInfoUpdated(UserInfo(userID: previewViewer));
      await drainPreview();
      expect(fixture.groups, hasLength(2));
      expect(fixture.roles, hasLength(2));
      expect(fixture.members, hasLength(2));

      fixture.groups.first.complete(previewGroup());
      fixture.roles.first.complete(previewRole());
      fixture.members.first.complete(previewMembers(id: 'old-peer'));
      await Future.wait([oldGroup, oldRole, oldMembers]);
      expect(setup.myGroupMembersInfo.value.roleLevel, isNull);
      expect(setup.groupInfo.value.memberCount, 0);
      expect(setup.memberList, isEmpty);

      if (membersFirst) {
        fixture.members.last.complete(previewMembers());
        await drainPreview();
      }
      fixture.groups.last.complete(previewGroup(privacy: 1));
      fixture.roles.last
          .complete(previewRole(role: GroupRoleLevel.member, manager: 0));
      await drainPreview();
      expect(setup.myGroupMembersInfo.value.roleLevel, GroupRoleLevel.member);
      expect(setup.groupInfo.value.memberCount, 10002);
      expect(fixture.members, hasLength(2));
      if (!membersFirst) {
        fixture.members.last.complete(previewMembers());
        await drainPreview();
      }
      expect(setup.memberList.single.userID, 'im_peer');
    });
  }

  test('self profile event preserves an unfinished initial membership check',
      () async {
    final setup = fixture.setup;
    setup.isJoinedGroup.value = false;
    setup.onReady();
    await drainPreview();
    fixture.im.selfInfoUpdated(UserInfo(userID: previewViewer));
    await drainPreview();
    expect(fixture.members, isEmpty);
    fixture.joined.single.complete('true');
    await drainPreview();
    expect(setup.isJoinedGroup.value, isTrue);
    expect(fixture.groups, hasLength(1));
    expect(fixture.roles, hasLength(1));
    expect(fixture.members, hasLength(1));
  });

  for (final change in [
    'leave',
    'self removed',
    'close',
    'account',
    'SDK account',
    'IM token',
    'server',
    'group',
  ]) {
    test('$change rejects a late member result', () async {
      final setup = fixture.setup;
      final old = setup.getGroupMembers();
      await drainPreview();
      switch (change) {
        case 'leave':
          fixture.im.joinedGroupDeleted(GroupInfo(groupID: previewGroupID));
        case 'self removed':
          fixture.im.groupMemberDeleted(GroupMembersInfo(
            groupID: previewGroupID,
            userID: previewViewer,
          ));
        case 'close':
          setup.onDelete();
        case 'account':
          await fixture.login(viewer: 'im_next');
        case 'SDK account':
          OpenIM.iMManager.userID = 'im_next';
        case 'IM token':
          await fixture.login(token: 'new-im-token');
        case 'server':
          await DataSp.putServerConfig({'apiUrl': 'http://new-group.test'});
        case 'group':
          setup.groupInfo.value = GroupInfo(groupID: 'another-group');
      }
      await drainPreview();
      fixture.members.single.complete(previewMembers());
      await old;
      expect(setup.memberList, isEmpty);
      final count = fixture.members.length;
      await setup.getGroupMembers();
      expect(fixture.members, hasLength(count));
    });
  }
}
