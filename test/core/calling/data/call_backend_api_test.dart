import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/calling/data/call_backend_api.dart';
import 'package:openim/core/push/apns/apns_platform.dart';

class Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object reply = {
    'errCode': 0,
    'data': {'registered': true, 'deviceID': 'device_one'}
  };
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(reply), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
      'separate VoIP registration uses captured Chat credential and environment',
      () async {
    final transport = Transport();
    final api = CallBackendApi(
        accountID: 'callee',
        token: 'chat-session',
        deviceID: 'device_one',
        baseUrl: 'https://chat.example/',
        client: Dio()..httpClientAdapter = transport);
    await api.bind(APNsDeviceToken(
        token: 'ab' * 32,
        bundleID: 'vip.99chat.ios',
        environment: 'production'));
    final req = transport.requests.single;
    expect(req.path, 'https://chat.example/calling/voip/register');
    expect(req.headers['token'], 'chat-session');
    expect(req.followRedirects, isFalse);
    expect((req.data as Map)['environment'], 'production');
    expect((req.data as Map).containsKey('userID'), isFalse);
    transport.reply = {'errCode': 409, 'data': {}};
    await expectLater(
        api.action('room_1234', 'accept'),
        throwsA(
            isA<CallBackendException>().having((e) => e.code, 'code', 409)));
    api.close();
  });
  test('HTTP success without OpenIM success envelope is rejected', () async {
    final transport = Transport()..reply = {'ok': true};
    final api = CallBackendApi(
        accountID: 'callee',
        token: 'chat-session',
        deviceID: 'device_one',
        baseUrl: 'https://chat.example',
        client: Dio()..httpClientAdapter = transport);
    await expectLater(
        api.status('room_1234'), throwsA(isA<CallBackendException>()));
    api.close();
  });
}
