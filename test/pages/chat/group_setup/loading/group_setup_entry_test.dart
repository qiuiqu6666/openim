import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
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
    expect(fixture.setup.isJoinedGroup.value, isFalse);
    expect(fixture.setup.isOwnerOrAdmin, isFalse);
    expect(fixture.setup.membership.resolved.value, isTrue);
    fixture.members.single.complete(previewMembers());
    await drainPreview();
    expect(fixture.setup.memberList, isEmpty);
  });
}
