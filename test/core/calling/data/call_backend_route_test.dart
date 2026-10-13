import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/calling/data/call_backend_api.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromString('{"errCode":0,"data":{}}', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Config.useRuntimeNetworkRoute(null);
    await DataSp.putServerConfig({'authUrl': 'https://custom.example'});
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'user', 'chatToken': 'chat-token', 'imToken': 'im-token'}));
  });
  tearDown(() => Config.useRuntimeNetworkRoute(null));

  test(
      'calling requests follow auth route and old client expires after switching',
      () async {
    final transport = _Transport();
    final api = CallBackendApi(
        accountID: 'user',
        token: 'chat-token',
        deviceID: 'device',
        baseUrl: Config.callingUrl,
        client: Dio()..httpClientAdapter = transport);
    await api.status('room_1234');
    expect(transport.requests.single.uri.toString(),
        'https://custom.example/calling/status');
    Config.useRuntimeNetworkRoute(const RuntimeNetworkRoute(
        authUrl: 'http://127.0.0.1:40008',
        apiUrl: 'http://127.0.0.1:40002',
        wsUrl: 'ws://127.0.0.1:40001',
        customerServiceUrl: 'http://127.0.0.1:48815'));
    expect(api.isCurrent, isFalse);
    await expectLater(
        api.status('room_1234'), throwsA(isA<CallBackendException>()));
    expect(transport.requests, hasLength(1));
    final protectedApi = CallBackendApi(
        accountID: 'user',
        token: 'chat-token',
        deviceID: 'device',
        baseUrl: Config.callingUrl,
        client: Dio()..httpClientAdapter = transport);
    await protectedApi.status('room_1234');
    expect(transport.requests.last.uri.toString(),
        'http://127.0.0.1:40008/calling/status');
    api.close();
    protectedApi.close();
  });
}
