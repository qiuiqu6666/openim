import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/core/server_nodes/route_history.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('remembers shield and replaces it only after confirmed direct success',
      () async {
    expect(await RouteHistory.read(), isNull);
    await RouteHistory.remember(NodeEndpoint.shield);
    expect(await RouteHistory.read(), NodeEndpoint.shield);
    await RouteHistory.remember(NodeEndpoint.backup);
    expect(await RouteHistory.read(), NodeEndpoint.backup);
  });
  test(
      'unknown persisted routes and custom endpoints cannot enable shield startup',
      () async {
    SharedPreferences.setMockInitialValues({RouteHistory.key: 'untrusted'});
    expect(await RouteHistory.read(), isNull);
    await RouteHistory.remember(const NodeEndpoint(
        chatApi: 'https://custom.test',
        imApi: 'https://custom.test/api',
        imWs: 'wss://custom.test/ws'));
    expect(await RouteHistory.read(), isNull);
  });
}
