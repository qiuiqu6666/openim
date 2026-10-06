import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/calls/data/call_records_runtime.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _credentials(String account) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': account,
    'chatToken': '$account-chat-token',
    'imToken': '$account-im-token',
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    CallRecordsRuntime.resetSession();
    CallRecordsRuntime.detachSync();
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });
  tearDown(() {
    CallRecordsRuntime.resetSession();
    CallRecordsRuntime.detachSync();
  });

  test('late cleanup for replaced account cannot dispose current repository',
      () async {
    final cache = CacheController();
    await _credentials('account-a');
    final old = CallRecordsRuntime.forAccount(cache);
    expect(CallRecordsRuntime.currentRepository, same(old));
    await _credentials('account-b');
    final current = CallRecordsRuntime.forAccount(cache);
    expect(old.isDisposed, isTrue);
    CallRecordsRuntime.resetSession(expected: old);
    expect(CallRecordsRuntime.currentRepository, same(current));
    expect(current.isDisposed, isFalse);
    CallRecordsRuntime.resetSession(expected: current);
    expect(CallRecordsRuntime.currentRepository, isNull);
    expect(current.isDisposed, isTrue);
  });
}
