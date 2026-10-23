import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/youmeng/native_shield_preparation.dart';

void main() {
  testWidgets('parallel requests share one native start', (tester) async {
    final native = Completer<void>();
    var starts = 0;
    final owner = NativeShieldPreparation(
        startNative: (_) {
          starts++;
          return native.future;
        },
        cancelNative: () async {});
    final first = owner.prepare();
    expect(owner.prepare(), same(first));
    await tester.pump();
    expect(starts, 1);
    native.complete();
    await tester.pump();
    await first;
  });

  testWidgets(
      'hung native times out, cancels, and allows a fresh initialization',
      (tester) async {
    var starts = 0, cancels = 0;
    final native = Completer<void>();
    final owner = NativeShieldPreparation(startNative: (_) {
      starts++;
      return starts == 1 ? native.future : Future.value();
    }, cancelNative: () async {
      cancels++;
    });
    final failed =
        expectLater(owner.prepare(), throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    await failed;
    expect(cancels, 1);
    final fresh = owner.prepare();
    await tester.pump();
    await fresh;
    expect(starts, 2);
    native.complete();
    await tester.pump();
    expect(cancels, 1);
  });

  testWidgets(
      'cancel settles Dart and late native completion cannot complete replacement',
      (tester) async {
    final operations = <Completer<void>>[];
    final cancellation = Completer<void>();
    final owner = NativeShieldPreparation(
        startNative: (_) {
          final op = Completer<void>();
          operations.add(op);
          return op.future;
        },
        cancelNative: () => cancellation.future);
    final old = expectLater(owner.prepare(), throwsStateError);
    await tester.pump();
    final cancel = owner.cancel();
    final next = owner.prepare();
    var nextDone = false;
    unawaited(next.then((_) => nextDone = true));
    await tester.pump();
    await old;
    expect(operations.length,
        1); // Must wait for native cancellation acknowledgement.
    operations.first.complete();
    await tester.pump();
    expect(nextDone, isFalse);
    cancellation.complete();
    await tester.pump();
    await cancel;
    expect(operations.length, 2);
    expect(nextDone, isFalse);
    operations.last.complete();
    await tester.pump();
    await next;
    expect(nextDone, isTrue);
  });

  testWidgets('failure cleans up once and successful standby is not cancelled',
      (tester) async {
    var cancels = 0, starts = 0;
    final owner = NativeShieldPreparation(startNative: (_) async {
      if (++starts == 1) throw StateError('failed');
    }, cancelNative: () async {
      cancels++;
    });
    final failed = expectLater(owner.prepare(), throwsStateError);
    await tester.pump();
    await failed;
    final ok = owner.prepare();
    await tester.pump();
    await ok;
    await owner.cancel();
    expect(cancels, 1);
  });
}
