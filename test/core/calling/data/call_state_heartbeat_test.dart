import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/calling/data/call_backend_api.dart';
import 'package:openim/core/calling/data/call_state_heartbeat.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HeartbeatApi extends CallBackendApi {
  HeartbeatApi()
      : super(
            accountID: 'caller',
            token: 'captured',
            deviceID: 'device_one',
            baseUrl: Config.appAuthUrl);
  int queries = 0;
  final actions = <String>[];
  bool closed = false, fail = false;
  String state = 'accepted';
  @override
  Future<Map<String, dynamic>> status(String room) async {
    queries++;
    if (fail) throw StateError('offline');
    return {'state': state};
  }

  @override
  Future<Map<String, dynamic>> action(String room, String action) async {
    actions.add(action);
    return {'state': 'ended'};
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'caller', 'chatToken': 'captured', 'imToken': 'im'}));
  });
  tearDown(CallStateHeartbeat.stopAll);

  testWidgets('live calls renew state and a terminal response stops polling',
      (tester) async {
    final api = HeartbeatApi();
    CallStateHeartbeat.start('room_1234', api);
    await tester.pump(const Duration(seconds: 10));
    expect(api.queries, 1);
    expect(api.closed, isFalse);
    api.state = 'ended';
    await tester.pump(const Duration(seconds: 10));
    expect(api.closed, isTrue);
    await tester.pump(const Duration(seconds: 20));
    expect(api.queries, 2);
    CallStateHeartbeat.stopAll();
  });
  testWidgets('logout stops the captured session before the next HTTP request',
      (tester) async {
    final api = HeartbeatApi();
    CallStateHeartbeat.start('room_1234', api);
    await DataSp.removeLoginCertificate();
    await tester.pump(const Duration(seconds: 10));
    expect(api.queries, 0);
    expect(api.closed, isTrue);
  });
  testWidgets('transient status failure allows the next heartbeat',
      (tester) async {
    final api = HeartbeatApi()..fail = true;
    CallStateHeartbeat.start('room_1234', api);
    await tester.pump(const Duration(seconds: 10));
    expect(api.queries, 1);
    expect(api.closed, isFalse);
    api.fail = false;
    await tester.pump(const Duration(seconds: 10));
    expect(api.queries, 2);
    CallStateHeartbeat.stopAll();
  });
  testWidgets(
      'closing media stops heartbeat and terminates abandoned server state',
      (tester) async {
    final api = HeartbeatApi();
    CallStateHeartbeat.start('room_1234', api);
    await CallStateHeartbeat.finish('room_1234');
    expect(api.actions, ['hangup']);
    expect(api.closed, isTrue);
    await tester.pump(const Duration(seconds: 20));
    expect(api.queries, 1);
  });
}
