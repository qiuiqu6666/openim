import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/upload/ready_media_batch.dart';

void main() {
  test('unprepared first video does not reserve the only video upload slot',
      () async {
    final first = Completer<void>();
    final sent = <int>[];
    final batch = runReadyMediaBatch([0, 1, 2],
        isVideo: (_) => true,
        waitUntilReady: (i) => i == 0 ? first.future : Future.value(),
        prepare: (_) async {},
        send: (i) async {
          sent.add(i);
        },
        onError: (_, error) => fail('$error'),
        isClosed: () => false);
    await Future<void>.delayed(Duration.zero);
    expect(sent, [1, 2]);
    first.complete();
    await batch;
    expect(sent, [1, 2, 0]);
  });

  test('four slow local images do not reserve all four upload slots', () async {
    final gates = List.generate(4, (_) => Completer<void>());
    final sent = <int>[];
    final batch = runReadyMediaBatch(List.generate(6, (i) => i),
        waitUntilReady: (i) => i < 4 ? gates[i].future : Future.value(),
        prepare: (_) async {},
        send: (i) async {
          sent.add(i);
        },
        onError: (_, error) => fail('$error'),
        isClosed: () => false);
    await Future<void>.delayed(Duration.zero);
    expect(sent, [4, 5]);
    for (final gate in gates) {
      gate.complete();
    }
    await batch;
    expect(sent.toSet(), {0, 1, 2, 3, 4, 5});
    expect(sent.length, 6);
  });
  test('pending receipts release upload slots but batch waits for all sends',
      () async {
    final receipts = List.generate(6, (_) => Completer<void>());
    final uploaded = <int>[], sent = <int>[];
    var completed = false;
    final work = runReadyMediaBatch(List.generate(6, (i) => i),
        prepare: (i) async => uploaded.add(i),
        send: (i) {
          sent.add(i);
          return receipts[i].future;
        },
        onError: (_, error) => fail('$error'),
        isClosed: () => false).then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(uploaded, [0, 1, 2, 3, 4, 5]);
    expect(sent, uploaded);
    expect(completed, isFalse);
    for (final receipt in receipts) {
      receipt.complete();
    }
    await work;
    expect(completed, isTrue);
  });

  test('ready images send while the first upload is still pending', () async {
    final gates = List.generate(6, (_) => Completer<void>());
    final started = <int>[];
    final sent = <int>[];
    var active = 0, peak = 0;
    final work = runReadyMediaBatch([0, 1, 2, 3, 4, 5],
        prepare: (int i) async {
          started.add(i);
          active++;
          if (active > peak) peak = active;
          await gates[i].future;
          active--;
        },
        send: (int i) async {
          sent.add(i);
        },
        onError: (_, error) => fail('$error'),
        isClosed: () => false);
    expect(started, [0, 1, 2, 3]);
    gates[1].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2, 3, 4]);
    expect(sent, [1]);
    gates[2].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2, 3, 4, 5]);
    gates[3].complete();
    await Future<void>.delayed(Duration.zero);
    gates[4].complete();
    await Future<void>.delayed(Duration.zero);
    gates[5].complete();
    await Future<void>.delayed(Duration.zero);
    expect(sent, [1, 2, 3, 4, 5]);
    gates[0].complete();
    await work;
    expect(sent, [1, 2, 3, 4, 5, 0]);
    expect(peak, 4);
  });
  test('multiple slow videos cannot occupy the image upload lane', () async {
    final videoGate = Completer<void>();
    final sent = <int>[];
    final work = runReadyMediaBatch([0, 1, 2, 3],
        isVideo: (i) => i < 2,
        prepare: (i) async {
          if (i < 2) await videoGate.future;
        },
        send: (i) async {
          sent.add(i);
        },
        onError: (_, error) => fail('$error'),
        isClosed: () => false);
    await Future<void>.delayed(Duration.zero);
    expect(sent, [2, 3]);
    videoGate.complete();
    await work;
    expect(sent, [2, 3, 0, 1]);
  });
  test('a send failure is reported once without retrying or blocking others',
      () async {
    final attempted = <int>[], failed = <int>[];
    await runReadyMediaBatch([0, 1, 2],
        prepare: (_) async {},
        send: (i) async {
          attempted.add(i);
          if (i == 0) throw StateError('send');
        },
        onError: (i, _) => failed.add(i),
        isClosed: () => false);
    expect(attempted, [0, 1, 2]);
    expect(failed, [0]);
  });
  test('one upload failure does not send that message or block the batch',
      () async {
    final sent = <int>[], failed = <int>[];
    await runReadyMediaBatch([0, 1, 2],
        prepare: (int i) async {
          if (i == 1) throw StateError('upload');
        },
        send: (int i) async {
          sent.add(i);
        },
        onError: (i, _) => failed.add(i),
        isClosed: () => false);
    expect(sent, [0, 2]);
    expect(failed, [1]);
  });
  test('closing or switching account stops later uploads and every send',
      () async {
    var closed = false;
    final sent = <int>[], started = <int>[];
    final gate = Completer<void>();
    final work = runReadyMediaBatch([0, 1, 2, 3, 4, 5],
        prepare: (int i) async {
          started.add(i);
          await gate.future;
        },
        send: (int i) async {
          sent.add(i);
        },
        onError: (_, error) => fail('$error'),
        isClosed: () => closed);
    closed = true;
    gate.complete();
    await work;
    expect(started, [0, 1, 2, 3]);
    expect(sent, isEmpty);
  });
}
