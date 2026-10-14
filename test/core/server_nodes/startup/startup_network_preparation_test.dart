import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/feedback/network_recovery_progress.dart';
import 'package:openim/core/server_nodes/startup/startup_network_preparation.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Config.useRuntimeNetworkRoute(null);
  });
  tearDown(() => Config.useRuntimeNetworkRoute(null));

  testWidgets('failed shield retries inside one startup and releases SDK once',
      (tester) async {
    final progress = NetworkRecoveryProgress();
    final attempts = <Completer<void>>[];
    final startup = StartupNetworkPreparation(
      progress: progress,
      prepareNetwork: (onShieldStarting) {
        onShieldStarting();
        final attempt = Completer<void>();
        attempts.add(attempt);
        return attempt.future;
      },
    );
    var sdkStarts = 0;
    final first = startup.prepare();
    unawaited(first.then((_) => sdkStarts++));
    expect(startup.prepare(), same(first));
    expect(attempts, hasLength(1));
    expect(progress.value?.stage, NetworkRecoveryStage.startingShield);
    expect(progress.value?.context, NetworkRecoveryContext.startup);
    attempts[0].completeError(StateError('shield not ready'));
    await tester.pump();
    expect(progress.value?.stage, NetworkRecoveryStage.retrying);
    expect(startup.ready, isFalse);
    expect(sdkStarts, 0);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(attempts, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(attempts, hasLength(2));
    attempts[1].completeError(StateError('still offline'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(attempts, hasLength(3));
    Config.useRuntimeNetworkRoute(const RuntimeNetworkRoute(
        authUrl: 'http://127.0.0.1:10008',
        apiUrl: 'http://127.0.0.1:10002',
        wsUrl: 'ws://127.0.0.1:10001',
        customerServiceUrl: 'http://127.0.0.1:8815'));
    attempts[2].complete();
    await tester.pump();
    expect(startup.ready, isTrue);
    expect(sdkStarts, 1);
    expect(dio.options.baseUrl, 'http://127.0.0.1:10002');
    expect(progress.value, isNull);
    await startup.prepare();
    expect(attempts, hasLength(3));
    startup.onClose();
    progress.dispose();
  });

  testWidgets('close cancels retry without reporting a ready route',
      (tester) async {
    final progress = NetworkRecoveryProgress();
    var attempts = 0;
    final startup = StartupNetworkPreparation(
      progress: progress,
      prepareNetwork: (_) async {
        attempts++;
        throw StateError('offline');
      },
    );
    final future = startup.prepare();
    await tester.pump();
    startup.onClose();
    await tester.pump(const Duration(minutes: 1));
    await future;
    expect(attempts, 1);
    expect(startup.ready, isFalse);
    expect(progress.value, isNull);
    progress.dispose();
  });

  testWidgets('a late native result cannot revive closed startup feedback',
      (tester) async {
    final progress = NetworkRecoveryProgress();
    final native = Completer<void>();
    late void Function() starting;
    final startup = StartupNetworkPreparation(
        progress: progress,
        prepareNetwork: (callback) {
          starting = callback;
          return native.future;
        });
    final future = startup.prepare();
    startup.onClose();
    starting();
    native.complete();
    await tester.pump();
    await future;
    expect(startup.ready, isFalse);
    expect(progress.value, isNull);
    progress.dispose();
  });
}
