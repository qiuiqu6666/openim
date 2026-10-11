import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group/chat_group_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountingMember extends GroupMembersInfo {
  CountingMember(int i)
      : super(
            groupID: 'g',
            userID: 'u$i',
            nickname: 'name$i',
            roleLevel: GroupRoleLevel.member,
            joinTime: i);
  static int nicknameReads = 0;
  static int joinTimeReads = 0;
  @override
  String? get nickname {
    nicknameReads++;
    return super.nickname;
  }

  @override
  int? get joinTime {
    joinTimeReads++;
    return super.joinTime;
  }
}

class CountingMessages extends RxList<Message> {
  CountingMessages(super.initial);
  int scans = 0, refreshes = 0;
  @override
  Iterator<Message> get iterator => counted().iterator;
  Iterable<Message> counted() sync* {
    for (var i = 0; i < length; i++) {
      scans++;
      yield this[i];
    }
  }

  @override
  void refresh() {
    refreshes++;
    super.refresh();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'me';
  });
  test('production group event and @ mapping operation counters', () async {
    final added = StreamController<GroupMembersInfo>.broadcast(sync: true);
    final changed = StreamController<GroupMembersInfo>.broadcast(sync: true);
    final messages = CountingMessages(List.generate(
        300,
        (i) => Message(
            clientMsgID: '$i',
            sendID: 'sender$i',
            contentType: MessageType.text)));
    final controller = ChatGroupController.withSources(
        events: ChatGroupEvents(
            joined: const Stream.empty(),
            left: const Stream.empty(),
            memberAdded: added.stream,
            memberDeleted: const Stream.empty(),
            memberChanged: changed.stream,
            groupChanged: const Stream.empty()),
        queries: ChatGroupQueries(
            isJoined: (_) async => true,
            groupInfo: (_) async => [],
            selfMember: (_, __) async => [],
            ownerAndAdmin: (_) async => []),
        groupID: () => 'g',
        currentUserID: () => 'me',
        messages: messages,
        clearInput: () {},
        onGroupProfileChanged: (_, __) {});
    controller.initialize();
    for (var i = 0; i < 5000; i++) {
      added.add(CountingMember(i));
    }
    expect(controller.memberUpdateInfoMap.length, 5000);
    // Model a long-lived chat that has actually seen 5000 distinct member
    // updates. Merely being in a 5000-member group does NOT fill this cache.
    CountingMember.nicknameReads = 0;
    for (var i = 0; i < 20; i++) {
      expect(controller.getAtMapping(Message(contentType: MessageType.text)),
          isEmpty);
    }
    expect(CountingMember.nicknameReads, 0);
    messages.scans = 0;
    messages.refreshes = 0;
    for (var i = 0; i < 100; i++) {
      changed.add(GroupMembersInfo(
          groupID: 'g',
          userID: 'absent$i',
          nickname: 'unchanged',
          roleLevel: GroupRoleLevel.member));
    }
    expect(messages.scans, lessThanOrEqualTo(300));
    expect(messages.refreshes, 0);
    controller.close();
    await added.close();
    await changed.close();
  });
}
