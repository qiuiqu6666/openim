import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'group_preview_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('full recovery member burst keeps the preview bounded', () async {
    final fixture = GroupPreviewFixture();
    await fixture.initialize();
    addTearDown(fixture.close);
    for (var index = 0; index < 1005; index++) {
      fixture.im.groupMemberAdded(GroupMembersInfo(
          groupID: previewGroupID, userID: 'member-$index', joinTime: index));
    }
    await drainPreview();
    expect(fixture.setup.memberList, hasLength(20));
    expect(fixture.setup.memberList.first.userID, 'member-1004');
  });

  test(
      'member events survive an older preview and repeated additions deduplicate',
      () async {
    final fixture = GroupPreviewFixture();
    await fixture.initialize();
    addTearDown(fixture.close);
    final setup = fixture.setup;
    final pending = setup.getGroupMembers();
    await drainPreview();
    fixture.im.groupMemberInfoChanged(GroupMembersInfo(
        groupID: previewGroupID, userID: 'rename', nickname: 'New nickname'));
    fixture.im.groupMemberDeleted(
        GroupMembersInfo(groupID: previewGroupID, userID: 'remove'));
    final added = GroupMembersInfo(
        groupID: previewGroupID, userID: 'add', nickname: 'Added');
    fixture.im.groupMemberAdded(added);
    fixture.im.groupMemberAdded(added);
    await drainPreview();
    fixture.members.single.complete({
      'members': [
        {
          'groupID': previewGroupID,
          'userID': 'rename',
          'nickname': 'Old nickname'
        },
        {'groupID': previewGroupID, 'userID': 'remove', 'nickname': 'Removed'},
        {'groupID': previewGroupID, 'userID': 'add', 'nickname': 'Added'},
      ]
    });
    await pending;
    expect(setup.memberList.map((m) => m.userID).toSet(), {'rename', 'add'});
    expect(setup.memberList, hasLength(2));
    expect(setup.memberList.singleWhere((m) => m.userID == 'rename').nickname,
        'New nickname');
  });

  test('self member event supersedes a pending nickname and role query',
      () async {
    final fixture = GroupPreviewFixture();
    await fixture.initialize();
    addTearDown(fixture.close);
    final setup = fixture.setup;
    final first = setup.getMyGroupMemberInfo();
    await drainPreview();
    fixture.roles.single.complete(previewRole());
    await first;
    final pending = setup.getMyGroupMemberInfo();
    await drainPreview();
    fixture.im.groupMemberInfoChanged(GroupMembersInfo(
      groupID: previewGroupID,
      userID: previewViewer,
      nickname: 'New self nickname',
      roleLevel: GroupRoleLevel.admin,
      appManagerLevel: 1,
    ));
    await drainPreview();
    fixture.roles.last.complete(previewRole());
    await pending;
    expect(setup.myGroupMembersInfo.value.nickname, 'New self nickname');
  });

  test('old group read cannot roll back a newer name and count event',
      () async {
    final fixture = GroupPreviewFixture();
    await fixture.initialize();
    addTearDown(fixture.close);
    final setup = fixture.setup;
    final initial = setup.getGroupInfo();
    await drainPreview();
    fixture.groups.single.complete(previewGroup());
    await initial;
    final pending = setup.getGroupInfo();
    await drainPreview();
    fixture.im.groupInfoChanged(GroupInfo(
      groupID: previewGroupID,
      groupName: 'New group name',
      memberCount: 10003,
      ownerUserID: 'im_owner',
      lookMemberInfo: 0,
    ));
    await drainPreview();
    expect(setup.groupInfo.value.groupName, 'New group name');
    expect(setup.groupInfo.value.memberCount, 10003);
    fixture.groups.last.complete(jsonEncode([
      GroupInfo(
              groupID: previewGroupID,
              groupName: 'Old group name',
              memberCount: 10002,
              ownerUserID: 'im_owner',
              lookMemberInfo: 0)
          .toJson(),
    ]));
    await pending;
    expect(setup.groupInfo.value.groupName, 'New group name');
    expect(setup.groupInfo.value.memberCount, 10003);
  });
}
