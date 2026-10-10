import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/contacts/group_requests/pagination/group_application_pager.dart';

import 'support/group_requests_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two SDK streams merge into ordered 20-item pages without omissions',
      () async {
    final incoming = [for (var i = 100; i > 0; i -= 2) request(time: i)];
    final outgoing = [for (var i = 99; i > 0; i -= 2) request(time: i)];
    final reads = <({bool recipient, int offset, int count})>[];
    final pager = GroupApplicationPager(read: (recipient, offset, count) async {
      reads.add((recipient: recipient, offset: offset, count: count));
      return (recipient ? incoming : outgoing)
          .skip(offset)
          .take(count)
          .toList();
    });
    final all = <GroupApplicationInfo>[];
    while (pager.hasMore) {
      final page = await pager.nextPage();
      expect(page.length, lessThanOrEqualTo(20));
      all.addAll(page);
    }
    expect(all.map((item) => item.reqTime), [for (var i = 100; i > 0; i--) i]);
    expect(reads.every((read) => read.count == 20), isTrue);
    for (final recipient in [true, false]) {
      expect(
          reads
              .where((read) => read.recipient == recipient)
              .map((r) => r.offset),
          [0, 20, 40]);
    }
  });

  test(
      'overlapping streams deduplicate and a failed fork does not consume rows',
      () async {
    var fail = false;
    final rows = [for (var i = 45; i > 0; i--) request(time: i)];
    final pager = GroupApplicationPager(read: (recipient, offset, count) async {
      if (fail && offset > 0) throw StateError('offline');
      return rows.skip(offset).take(count).toList();
    });
    expect((await pager.nextPage()).map((row) => row.reqTime),
        [for (var i = 45; i > 25; i--) i]);
    fail = true;
    await expectLater(pager.fork().nextPage(), throwsStateError);
    fail = false;
    expect((await pager.fork().nextPage()).map((row) => row.reqTime),
        [for (var i = 25; i > 5; i--) i]);
  });

  late GroupRequestsFixture fixture;
  setUp(() async {
    fixture = GroupRequestsFixture();
    await fixture.initialize();
  });
  tearDown(() async => fixture.dispose());

  testWidgets('SDK receives 20-item offsets; retry preserves loaded rows',
      (tester) async {
    fixture.recipient = [for (var i = 45; i > 0; i--) request(time: i)];
    final logic = await fixture.mount(tester);
    expect(logic.list, hasLength(20));
    fixture.failApplications = true;
    await logic.loadMore();
    expect(logic.list, hasLength(20));
    expect(logic.hasMore.value, isTrue);
    fixture.failApplications = false;
    await logic.loadMore();
    expect(
        logic.list.map((row) => row.reqTime), [for (var i = 45; i > 5; i--) i]);
    await logic.loadMore();
    expect(logic.list, hasLength(45));
    expect(logic.hasMore.value, isFalse);
    final requests = fixture.callsFor('getGroupApplicationListAsRecipient');
    expect(requests.map((call) => call.arguments['req']['count']),
        everyElement(20));
    expect(
        requests.map((call) => call.arguments['req']['offset']), [20, 20, 40]);
    final before = fixture.calls.length;
    await logic.loadMore();
    expect(fixture.calls.length, before);
  });

  testWidgets(
      'a refreshed page supersedes an in-flight load and keeps loaded range',
      (tester) async {
    fixture.recipient = [for (var i = 45; i > 0; i--) request(time: i)];
    final logic = await fixture.mount(tester);
    fixture.holdRecipient = true;
    final stale = logic.loadMore();
    await tester.pump();
    expect(fixture.recipientReplies, hasLength(1));
    fixture.holdRecipient = false;
    fixture.recipient = [for (var i = 100; i > 55; i--) request(time: i)];
    await fixture.refresh(tester, logic);
    fixture.recipientReplies.single
        .complete(jsonEncode([request(time: 25).toJson()]));
    await stale;
    expect(logic.list.map((row) => row.reqTime),
        [for (var i = 100; i > 80; i--) i]);
    await logic.loadMore();
    expect(logic.list, hasLength(40));
    await fixture.refresh(tester, logic);
    expect(logic.list, hasLength(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during pagination discards the late page',
      (tester) async {
    fixture.recipient = [for (var i = 45; i > 0; i--) request(time: i)];
    final logic = await fixture.mount(tester);
    fixture.holdRecipient = true;
    final pending = logic.loadMore();
    await tester.pump();
    Get.delete<GroupRequestsLogic>(force: true);
    fixture.recipientReplies.single.complete('[]');
    await pending;
    expect(logic.list, hasLength(20));
  });
}
