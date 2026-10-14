import 'package:flutter/widgets.dart';
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

  testWidgets('one server page includes names without SDK profile fan-out',
      (tester) async {
    fixture.recipient = [
      request(result: 1, handler: 'admin', inviter: 'inviter')
    ];
    fixture.profiles['admin'] = '处理人';
    final logic = await fixture.mount(tester);
    expect(logic.applicationsLoaded.value, isTrue);
    expect(logic.getHandlerNickname(logic.list.single), '处理人');
    expect(fixture.callsFor('getUsersInfo'), isEmpty);
    expect(fixture.callsFor('getJoinedGroupList'), isEmpty);
  });

  testWidgets('reopen waits for server visibility and deleted rows stay hidden',
      (tester) async {
    fixture.recipient = [request(time: 2), request(time: 1)];
    final first = await fixture.mount(tester);
    await first.deleteRequest(first.list.last);
    Get.delete<GroupRequestsLogic>(force: true);
    fixture.holdRecipient = true;
    final reopened = Get.put(GroupRequestsLogic(syncInterval: Duration.zero));
    expect(reopened.list, isEmpty);
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
    expect(fixture.noticeCalls.where((a) => a == 'list').length, 3);
  });

  testWidgets('late server page cannot update a replaced session',
      (tester) async {
    final logic = await fixture.mount(tester);
    fixture.holdRecipient = true;
    final pending = logic.reloadApplications();
    await tester.pump();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current-admin',
      'imToken': 'new-im',
      'chatToken': 'new-chat',
    }));
    fixture.recipientReplies.single.complete(jsonEncode([request().toJson()]));
    await tester.pumpAndSettle();
    await pending;
    expect(logic.list, isEmpty);
  });

  testWidgets('refresh remains one 20-row request after many pages',
      (tester) async {
    fixture.recipient = [for (var i = 2000; i > 0; i--) request(time: i)];
    final logic = await fixture.mount(tester);
    for (var i = 0; i < 5; i++) {
      await logic.loadMore();
    }
    expect(logic.list.length, 120);
    fixture.noticeCalls.clear();
    await logic.reloadApplications();
    expect(logic.list.length, 20);
    expect(fixture.noticeCalls.where((a) => a == 'list'), hasLength(1));
  });

  testWidgets(
      'remote clear invalidates an old cursor without resurrecting rows',
      (tester) async {
    fixture.recipient = [for (var i = 45; i > 0; i--) request(time: i)];
    final logic = await fixture.mount(tester);
    fixture.clearedThrough = 45000;
    fixture.serverRevision++;
    await logic.loadMore();
    expect(logic.list, isEmpty);
    expect(logic.hasMore.value, isFalse);
  });

  testWidgets('failed server deletion does not hide the row locally',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    fixture.failWrites = true;
    await logic.deleteRequest(logic.list.single);
    expect(logic.list, hasLength(1));
    expect(fixture.dismissed, isEmpty);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'foreground polling observes another device clear and stops in background',
      (tester) async {
    fixture.recipient = [request()];
    await fixture.mount(tester);
    Get.delete<GroupRequestsLogic>(force: true);
    final logic = Get.put(GroupRequestsLogic());
    await tester.pumpAndSettle();
    fixture.clearedThrough = 100000;
    fixture.serverRevision++;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(logic.list, isEmpty);
    logic.didChangeAppLifecycleState(AppLifecycleState.paused);
    fixture.noticeCalls.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(fixture.noticeCalls, isEmpty);
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.noticeCalls, contains('list'));
    Get.delete<GroupRequestsLogic>(force: true);
  });
  testWidgets(
      'an older review updates with one detail request after first-page refresh',
      (tester) async {
    fixture.recipient = [for (var i = 45; i > 0; i--) request(time: i)];
    final logic = await fixture.mount(tester);
    await logic.loadMore();
    final reviewed = logic.list.last;
    logic.trackReview(reviewed);
    fixture.recipient = [
      for (var row in fixture.recipient)
        row.reqTime == reviewed.reqTime
            ? request(time: row.reqTime!, result: 1, handler: 'admin')
            : row
    ];
    fixture.profiles['admin'] = '实际管理员';
    fixture.noticeCalls.clear();
    await logic.reloadApplications();
    expect(logic.list, hasLength(20));
    final updated = logic.findApplication(reviewed)!;
    expect(updated.handleResult, 1);
    expect(logic.getHandlerNickname(updated), '实际管理员');
    expect(fixture.noticeCalls.where((a) => a == 'detail'), hasLength(1));
    expect(fixture.noticeCalls.where((a) => a == 'list'), hasLength(1));
    logic.endReview();
  });
}
