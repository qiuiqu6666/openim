import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a burst of logs probes device info once and tolerates plugin failure',
      () async {
    const channel = MethodChannel('dev.fluttercommunity.plus/device_info');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var queries = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      queries++;
      throw PlatformException(code: 'unavailable');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (var index = 0; index < 100; index++) {
      Logger.print('visible $index', onlyConsole: true);
    }
    await Future<void>.delayed(Duration.zero);
    expect(queries, 1);
    Logger.print('after platform failure', onlyConsole: true);
    await Future<void>.delayed(Duration.zero);
    expect(queries, 1);
    expect(Logger(), same(Logger()));
  });
}
