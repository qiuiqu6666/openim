import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/session_request_errors.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'current';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current',
      'chatToken': 'current-token',
      'imToken': 'im',
    }));
  });

  test(
      'stale account and stale token authentication failures cannot expire the current account',
      () async {
    final events = <dynamic>[];
    final sub = Apis.kickoffController.stream.listen(events.add);
    expect(
        handleSessionAuthFailure((1503, 'expired'),
            account: 'old', token: 'current-token'),
        isFalse);
    expect(
        handleSessionAuthFailure((1503, 'expired'),
            account: 'current', token: 'old-token'),
        isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    expect(DataSp.userID, 'current');
    await sub.cancel();
  });

  test(
      'current-token auth failures are recognized without duplicating HTTP events',
      () async {
    final events = <dynamic>[];
    final sub = Apis.kickoffController.stream.listen(events.add);
    expect(
        handleSessionAuthFailure((1503, 'expired'),
            account: 'current', token: 'current-token'),
        isTrue);
    expect(
        handleSessionAuthFailure((1502, 'invalid'),
            account: 'current', token: 'current-token'),
        isTrue);
    expect(
        handleSessionAuthFailure((1507, 'missing'),
            account: 'current', token: 'current-token'),
        isTrue);
    expect(
        handleSessionAuthFailure((1506, 'expired'),
            account: 'current', token: 'current-token'),
        isTrue);
    expect(
        handleSessionAuthFailure((20101, 'expired'),
            account: 'current', token: 'current-token'),
        isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    await sub.cancel();
  });
}
