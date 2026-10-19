import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('default and persisted verbose settings remain aggregate-only', () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    expect(Config.logLevel, 4);
    expect(Config.logStandardOutput, false);
    for (final value in ['5', '6', 'invalid']) {
      await DataSp.putServerConfig({'logLevel': value});
      expect(Config.logLevel, 4);
    }
    await DataSp.putServerConfig({'logLevel': '3'});
    expect(Config.logLevel, 3);
  });
}
