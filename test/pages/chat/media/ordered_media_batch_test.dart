import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/upload/ordered_media_batch.dart';

void main() {
  test('uploads overlap at most two and delivery preserves selected order',
      () async {
    final gates = List.generate(4, (_) => Completer<void>());
    final started = <int>[];
    final sent = <int>[];
    var active = 0, peak = 0;
    final work = runOrderedMediaBatch([0, 1, 2, 3],
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
    expect(sent, isEmpty);
    gates[2].complete();
    await Future<void>.delayed(Duration.zero);
    gates[3].complete();
    gates[0].complete();
    await work;
    expect(sent, [0, 1, 2, 3]);
    expect(peak, 2);
  });
  test('one upload failure does not send that message or block the batch',
      () async {
    final sent = <int>[], failed = <int>[];
    await runOrderedMediaBatch([0, 1, 2],
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
    final work = runOrderedMediaBatch([0, 1, 2, 3],
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
