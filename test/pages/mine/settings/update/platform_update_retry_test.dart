import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/update/platform_update_retry.dart';

void main() {
  test('transient failure retries with bounded backoff', () async {
    var attempts = 0;
    final delays = <Duration>[];
    final result = await retryPlatformUpdate(() async {
      if (++attempts < 3) throw StateError('offline');
      return 'policy';
    }, wait: (delay) async => delays.add(delay));
    expect(result, 'policy');
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 3)]);
  });
  test('exhaustion remains an error and a new request can recover', () async {
    var attempts = 0;
    await expectLater(
        retryPlatformUpdate(() async {
          attempts++;
          throw StateError('offline');
        }, wait: (_) async {}),
        throwsStateError);
    expect(attempts, 3);
    expect(await retryPlatformUpdate(() async => 'recovered'), 'recovered');
  });
}
