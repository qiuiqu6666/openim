import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/upload/ready_media_batch.dart';

void main() {
  test('ready images send while the first upload is still pending', () async {
    final gates = List.generate(4, (_) => Completer<void>());
    final started = <int>[];
    final sent = <int>[];
    var active = 0, peak = 0;
    final work = runReadyMediaBatch([0, 1, 2, 3],
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
    expect(started, [0, 1]);
    gates[1].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2]);
    expect(sent, [1]);
    gates[2].complete();
    await Future<void>.delayed(Duration.zero);
    gates[3].complete();
    await Future<void>.delayed(Duration.zero);
    expect(sent, [1, 2, 3]);
    gates[0].complete();
    await work;
    expect(sent, [1, 2, 3, 0]);
    expect(peak, 2);
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
    final work = runReadyMediaBatch([0, 1, 2, 3],
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
    expect(started, [0, 1]);
    expect(sent, isEmpty);
  });
}
