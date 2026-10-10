import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/legacy_identity/legacy_server_snapshot.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  test('default service endpoints use HTTPS and WSS', () {
    expect(Config.appAuthUrl, 'https://99chatapi.99chat.vip');
    expect(Config.imApiUrl, 'https://99imapi.99chat.vip');
    expect(Config.imWsUrl, 'wss://websocket.99chat.vip');
  });

  test('saved previous endpoints migrate to the corresponding domains',
      () async {
    await DataSp.putServerConfig({
      'authUrl': 'http://129.226.192.93:10008/',
      'apiUrl': 'http://129.226.192.93:10002',
      'wsUrl': 'ws://129.226.192.93:10001',
    });
    expect(Config.appAuthUrl, Config.defaultChatApiUrl);
    expect(Config.imApiUrl, Config.defaultIMApiUrl);
    expect(Config.imWsUrl, Config.defaultIMWsUrl);
  });

  test('custom endpoints and path prefixes retain their configuration',
      () async {
    await DataSp.putServerConfig({
      'authUrl': 'https://custom.example/chat',
      'apiUrl': 'http://129.226.192.93:10002/custom',
      'wsUrl': 'wss://custom.example/ws',
    });
    expect(Config.appAuthUrl, 'https://custom.example/chat');
    expect(Config.imApiUrl, 'http://129.226.192.93:10002/custom');
    expect(Config.imWsUrl, 'wss://custom.example/ws');
  });

  test('legacy conversation cleanup accepts the HTTPS OpenIM domain only', () {
    expect(LegacyServerSnapshot.allowedServer(Config.defaultIMApiUrl), isTrue);
    expect(LegacyServerSnapshot.allowedServer('http://99imapi.99chat.vip'),
        isFalse);
    expect(
        LegacyServerSnapshot.allowedServer('https://other.example'), isFalse);
    expect(
        LegacyServerSnapshot.allowedServer('https://99imapi.99chat.vip:8443'),
        isFalse);
    expect(
        LegacyServerSnapshot.allowedServer('https://99imapi.99chat.vip/custom'),
        isFalse);
  });
}
