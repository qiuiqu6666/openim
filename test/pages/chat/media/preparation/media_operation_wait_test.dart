import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/preparation/media_operation_wait.dart';

void main() {
  test('repeated progress cannot hide a stalled operation', () async {
    final progress = StreamController<double>();
    final native = Completer<int>();
    final timer = Timer.periodic(
        const Duration(milliseconds: 5), (_) => progress.add(0.5));
    try {
      await expectLater(
          waitMediaOperation(native.future,
              totalTimeout: const Duration(seconds: 1),
              idleTimeout: const Duration(milliseconds: 30),
              isCancelled: () => false,
              progress: progress.stream),
          throwsA(isA<TimeoutException>()));
    } finally {
      timer.cancel();
      native.complete(1);
      await progress.close();
    }
  });
  test('increasing progress never extends total budget', () async {
    final progress = StreamController<double>();
    final native = Completer<int>();
    var n = 0;
    final timer = Timer.periodic(
        const Duration(milliseconds: 5), (_) => progress.add((++n).toDouble()));
    try {
      await expectLater(
          waitMediaOperation(native.future,
              totalTimeout: const Duration(milliseconds: 40),
              idleTimeout: const Duration(seconds: 1),
              isCancelled: () => false,
              progress: progress.stream),
          throwsA(isA<TimeoutException>()));
    } finally {
      timer.cancel();
      native.complete(1);
      await progress.close();
    }
  });
}
