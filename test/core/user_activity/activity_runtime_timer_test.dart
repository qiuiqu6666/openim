import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/user_activity/activity_runtime.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });

  testWidgets('30 second scheduling pauses in background and stops on disposal',
      (tester) async {
    final runtime = ActivityRuntime.instance;
    runtime.dispose();
    runtime.setForeground(true);
    addTearDown(runtime.dispose);
    var checks = 0;
    bool ready() {
      checks++;
      return false;
    }

    runtime.configure(sessionReady: ready);
    runtime.configure(sessionReady: ready);
    await tester.pump(const Duration(seconds: 29));
    expect(checks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(checks, 1);

    runtime.setForeground(false);
    runtime.configure(sessionReady: ready);
    await tester.pump(const Duration(minutes: 5));
    expect(checks, 1);

    runtime.setForeground(true);
    runtime.setForeground(true);
    await tester.pump(const Duration(seconds: 29));
    expect(checks, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(checks, 2);
    runtime.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(checks, 2);
  });
}
