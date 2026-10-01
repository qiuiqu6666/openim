import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language accepts current integers and legacy numeric strings', () async {
    for (final value in <Object>[0, 1, 2, '0', '1', ' 2 ']) {
      SharedPreferences.setMockInitialValues({'language': value});
      await SpUtil().init();
      expect(DataSp.getLanguage(), int.parse(value.toString().trim()));
    }
  });

  test('missing or invalid language falls back to system without throwing',
      () async {
    for (final value in <Object?>[null, '', 'invalid', 'zh_CN', -1, 3, true, 1.5]) {
      SharedPreferences.setMockInitialValues({
        if (value != null) 'language': value,
        'unrelatedPreference': 'keep',
      });
      await SpUtil().init();
      expect(DataSp.getLanguage(), 0);
      expect(SpUtil().getString('unrelatedPreference'), 'keep');
    }
  });

  test('choosing a language replaces a stale string with an integer', () async {
    SharedPreferences.setMockInitialValues({'language': 'invalid'});
    await SpUtil().init();
    await DataSp.putLanguage(2);
    expect(DataSp.getLanguage(), 2);
    expect(SpUtil().getDynamic('language'), 2);
  });
}
