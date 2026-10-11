import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim_common/openim_common.dart';

import 'support/group_requests_test_fixture.dart';

void main() {
  late GroupRequestsFixture fixture;
  setUp(() async {
    fixture = GroupRequestsFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.dispose());

  testWidgets('list does not wait for either profile source', (tester) async {
    fixture.recipient = [
      request(result: 1, handler: 'admin', inviter: 'inviter')
    ];
    fixture.holdMembers = fixture.holdProfiles = true;
    final logic = await fixture.mount(tester);
    expect(logic.applicationsLoaded.value, isTrue);
    expect(logic.list, hasLength(1));
    expect(fixture.memberReplies, hasLength(1));
    expect(fixture.profileReplies, hasLength(1));
    fixture.profileReplies.single.complete(jsonEncode([
      {'userID': 'admin', 'nickname': '处理人'},
    ]));
    await tester.pumpAndSettle();
    expect(logic.getHandlerNickname(logic.list.single), '处理人');
    expect(fixture.memberReplies.single.isCompleted, isFalse);
  });

  testWidgets(
      'reopen paints snapshot while SDK waits and deleted rows stay hidden',
      (tester) async {
    fixture.recipient = [request(time: 2), request(time: 1)];
    final first = await fixture.mount(tester);
    await first.deleteRequest(first.list.last);
    Get.delete<GroupRequestsLogic>(force: true);
    fixture.holdRecipient = true;
    final reopened = Get.put(GroupRequestsLogic());
    expect(reopened.list.map((row) => row.reqTime), [2]);
    expect(reopened.applicationsLoaded.value, isFalse,
        reason:
            'a snapshot must not enable paging with an uninitialized cursor');
    await tester.pump();
    expect(fixture.recipientReplies, hasLength(1));
    fixture.recipientReplies.single.complete(
        jsonEncode(fixture.recipient.map((row) => row.toJson()).toList()));
    await tester.pumpAndSettle();
    expect(reopened.list.map((row) => row.reqTime), [2]);
  });

  testWidgets('burst notifications queue one fresh read after the pending one',
      (tester) async {
    final logic = await fixture.mount(tester);
    fixture.holdRecipient = true;
    final read = logic.getApplicationList();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      fixture.im.groupApplicationChangedSubject.add(request());
    }
    await tester.pump();
    expect(fixture.recipientReplies, hasLength(1));
    fixture.recipientReplies[0]
        .complete(jsonEncode([request(time: 1).toJson()]));
    await tester.pumpAndSettle();
    expect(fixture.recipientReplies, hasLength(2));
    expect(logic.list, isEmpty, reason: 'superseded results must not repaint');
    fixture.recipientReplies[1]
        .complete(jsonEncode([request(time: 2).toJson()]));
    await tester.pumpAndSettle();
    await read;
    expect(logic.list.single.reqTime, 2);
    expect(
        fixture.callsFor('getGroupApplicationListAsRecipient'), hasLength(2));
  });

  testWidgets('late profiles cannot update a closed or replaced session',
      (tester) async {
    fixture.recipient = [request(result: 1, handler: 'admin')];
    fixture.holdProfiles = true;
    final logic = await fixture.mount(tester);
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current-admin',
      'imToken': 'new-im',
      'chatToken': 'new-chat',
    }));
    fixture.profileReplies.single.complete(jsonEncode([
      {'userID': 'admin', 'nickname': '旧账号'}
    ]));
    await tester.pumpAndSettle();
    expect(logic.userInfoList, isEmpty);
    Get.delete<GroupRequestsLogic>(force: true);
    final reopened = Get.put(GroupRequestsLogic());
    expect(reopened.list, isEmpty);
    Get.delete<GroupRequestsLogic>(force: true);
  });
}
