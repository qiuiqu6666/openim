import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/apis/auth/legacy_password_envelope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });
  void expectDirect() {
    expect(Config.appAuthUrl, 'http://129.226.192.93:10008');
    expect(Config.imApiUrl, 'http://129.226.192.93:10002');
    expect(Config.imWsUrl, 'ws://129.226.192.93:10001');
  }

  test('default endpoints use the requested direct route', expectDirect);
  test('saved retired domain node resolves to the direct route', () async {
    await DataSp.putServerConfig({
      'authUrl': 'https://99chatapi.99chat.vip',
      'apiUrl': 'https://99imapi.99chat.vip',
      'wsUrl': 'wss://websocket.99chat.vip',
    });
    expectDirect();
    await DataSp.putServerConfig({
      'authUrl': ' https://99chatapi.99chat.vip/ ',
      'apiUrl': 'https://99imapi.99chat.vip/',
      'wsUrl': 'wss://websocket.99chat.vip/',
    });
    expectDirect();
  });
  test('selected direct fallback remains effective for this launch', () async {
    await DataSp.putServerConfig({
      'authUrl': 'http://129.226.192.93:10008/',
      'apiUrl': 'http://129.226.192.93:10002',
      'wsUrl': 'ws://129.226.192.93:10001',
    });
    expect(Config.appAuthUrl, 'http://129.226.192.93:10008');
    expect(Config.imApiUrl, 'http://129.226.192.93:10002');
    expect(Config.imWsUrl, 'ws://129.226.192.93:10001');
  });
  test('explicit custom endpoints remain configured', () async {
    await DataSp.putServerConfig({
      'authUrl': 'https://custom.example/chat',
      'apiUrl': 'https://custom.example/api',
      'wsUrl': 'wss://custom.example/ws',
    });
    expect(Config.appAuthUrl, 'https://custom.example/chat');
    expect(Config.imApiUrl, 'https://custom.example/api');
    expect(Config.imWsUrl, 'wss://custom.example/ws');
  });
  test('legacy login proof allows only exact secure deployment domain', () {
    expect(
        LegacyPasswordEnvelope.permits(
            Uri.parse('https://99chatapi.99chat.vip/account/login')),
        isTrue);
    for (final url in [
      'http://99chatapi.99chat.vip/account/login',
      'https://99chatapi.99chat.vip.attacker/account/login',
      'https://user@99chatapi.99chat.vip/account/login',
      'https://99chatapi.99chat.vip:8443/account/login',
    ]) {
      expect(LegacyPasswordEnvelope.permits(Uri.parse(url)), isFalse);
    }
  });
}
