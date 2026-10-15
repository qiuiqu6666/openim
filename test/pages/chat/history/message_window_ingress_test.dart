import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

MessageWindow window(int through, {String id = 'chat'}) =>
    MessageWindow.fromJson({
      'version': 1,
      'conversationID': id,
      'targetWatermark': through,
      'lowerBound': through > 39 ? through - 39 : 1,
      'covered': [
        [through > 39 ? through - 39 : 1, through]
      ],
      'missing': [],
      'publishable': true,
      'source': 'remote',
      'visibilityKey': 'member:1',
      'snapshotRevision': '$through',
    });
Message row(int seq) =>
    Message(clientMsgID: 'm$seq', seq: seq, status: MessageStatus.succeeded);

void main() {
  testWidgets('out-of-order 5003,5001,5002 publishes one contiguous batch',
      (tester) async {
    final batches = <List<int?>>[];
    var recoveries = 0;
    final ingress = MessageWindowIngress(
        conversationID: 'chat',
        publish: (rows) => batches.add(rows.map((m) => m.seq).toList()),
        recover: () => recoveries++);
    ingress.accept(window(5000));
    ingress.receive(row(5003));
    ingress.receive(row(5001));
    ingress.receive(row(5002));
    expect(batches, isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    expect(batches, [
      [5001, 5002, 5003]
    ]);
    expect(recoveries, 0);
    ingress
        .accept(window(5000)); // late snapshot must not regress the live edge
    ingress.receive(row(5004));
    await tester.pump(const Duration(milliseconds: 16));
    expect(batches.last, [5004]);
    ingress.close();
  });

  testWidgets('gap is not exposed and recovery is coalesced', (tester) async {
    final published = <Message>[];
    var recoveries = 0;
    final ingress = MessageWindowIngress(
        conversationID: 'chat',
        publish: published.addAll,
        recover: () => recoveries++);
    ingress.accept(window(5000));
    ingress.receive(row(5003));
    await tester.pump(const Duration(milliseconds: 16));
    expect(published, isEmpty);
    expect(recoveries, 1);
    ingress.receive(row(5004));
    await tester.pump(const Duration(milliseconds: 16));
    expect(recoveries, 1);
    ingress.accept(window(5002));
    await tester.pump(const Duration(milliseconds: 16));
    expect(published.map((m) => m.seq), [5003, 5004]);
    ingress.close();
  });

  testWidgets('overflow stays bounded and re-reads persisted events',
      (tester) async {
    var recoveries = 0;
    final published = <Message>[];
    final ingress = MessageWindowIngress(
        conversationID: 'chat',
        capacity: 200,
        publish: published.addAll,
        recover: () => recoveries++);
    ingress.accept(window(5000));
    for (var i = 5001; i <= 15000; i++) {
      ingress.receive(row(i));
      expect(ingress.pendingCount, lessThanOrEqualTo(200));
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(recoveries, 1);
    expect(published, isEmpty);
    ingress.accept(window(15000));
    ingress.receive(row(15001));
    await tester.pump(const Duration(milliseconds: 16));
    expect(published.single.seq, 15001);
    ingress.close();
  });

  testWidgets('A/B owners, clear and close reject stale buffered work',
      (tester) async {
    final aRows = <Message>[], bRows = <Message>[];
    final a = MessageWindowIngress(
        conversationID: 'A', publish: aRows.addAll, recover: () {});
    final b = MessageWindowIngress(
        conversationID: 'B', publish: bRows.addAll, recover: () {});
    a.accept(window(10, id: 'A'));
    b.accept(window(50, id: 'B'));
    b.accept(window(100, id: 'A')); // wrong conversation ignored
    a.receive(row(11));
    b.receive(row(51));
    a.close();
    await tester.pump(const Duration(milliseconds: 16));
    expect(aRows, isEmpty);
    expect(bRows.single.seq, 51);
    b.receive(row(52));
    b.reset();
    await tester.pump(const Duration(milliseconds: 16));
    expect(bRows.length, 1);
    expect(b.active, isFalse);
    b.close();
  });

  testWidgets('delete of a queued message preserves its sequence coverage',
      (tester) async {
    final published = <Message>[];
    final ingress = MessageWindowIngress(
        conversationID: 'chat', publish: published.addAll, recover: () {});
    ingress.accept(window(50));
    ingress.receive(row(51));
    ingress.remove('m51');
    ingress.receive(row(52));
    await tester.pump(const Duration(milliseconds: 16));
    expect(published.first.status, MessageStatus.deleted);
    expect(published.last.seq, 52);
    ingress.close();
  });

  testWidgets('sustained 10000 messages use 125 bounded UI batches',
      (tester) async {
    var batches = 0;
    final published = <int>[];
    final ingress = MessageWindowIngress(
        conversationID: 'chat',
        publish: (rows) {
          batches++;
          published.addAll(rows.map((m) => m.seq!));
        },
        recover: () => fail('unexpected gap'));
    ingress.accept(window(5000));
    for (var start = 5001; start <= 15000; start += 80) {
      for (var i = start; i < start + 80; i++) {
        ingress.receive(row(i));
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(batches, 125);
    expect(published, List.generate(10000, (i) => 5001 + i));
    expect(ingress.pendingCount, 0);
    ingress.close();
  });
}
