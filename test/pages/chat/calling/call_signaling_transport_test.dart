import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:openim_live/src/models/call_errors.dart';
import 'package:openim_live/src/signaling/call_error_message.dart';
import 'package:openim_live/src/signaling/call_signaling_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RTCAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object? payload = {'token': 'rtc-token', 'liveURL': 'wss://rtc.example.test'};
  bool networkFailure = false;
  int errCode = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? request,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (networkFailure) {
      throw DioException.connectionTimeout(
          requestOptions: options, timeout: const Duration(seconds: 30));
    }
    return ResponseBody.fromString(
        jsonEncode({
          'errCode': errCode,
          'errMsg': errCode == 0 ? '' : 'server diagnostics',
          'data': payload,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _RTCAdapter adapter;
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'alice',
      'chatToken': 'chat-secret',
      'imToken': 'im-secret',
    }));
    http.dio = Dio();
    HttpUtil.init();
    adapter = _RTCAdapter();
    http.dio.httpClientAdapter = adapter;
  });
  tearDown(() {
    http.dio.close(force: true);
    Get.reset();
  });

  test('uses the existing authenticated RTC payload and binds its call ID',
      () async {
    final certificate = await requestRtcCertificate('call-123456', 'alice');
    expect(certificate.roomID, 'call-123456');
    expect(certificate.token, 'rtc-token');
    expect(adapter.requests.single.path, Urls.getTokenForRTC);
    expect(adapter.requests.single.data,
        {'room': 'call-123456', 'identity': 'alice'});
    expect(adapter.requests.single.headers['token'], 'chat-secret');
  });

  test('serverUrl and token response binds the requested room ID', () async {
    adapter.payload = {
      'serverUrl': 'ws://rtc.example.test:7880',
      'token': 'test-server-url-token',
    };

    final certificate = await requestRtcCertificate('call-123456', 'alice');

    expect(certificate.liveURL, 'ws://rtc.example.test:7880');
    expect(certificate.token, 'test-server-url-token');
    expect(certificate.roomID, 'call-123456');
    expect(adapter.requests.single.path, Urls.getTokenForRTC);
    expect(adapter.requests.single.data,
        {'room': 'call-123456', 'identity': 'alice'});
    expect(adapter.requests.single.headers['token'], 'chat-secret');
  });

  test('a nonempty legacy liveURL takes priority over serverUrl', () async {
    adapter.payload = {
      'token': 'rtc-token',
      'liveURL': 'wss://legacy-rtc.example.test',
      'serverUrl': 'ws://new-rtc.example.test:7880',
      'roomID': 'call-123456',
    };

    final certificate = await requestRtcCertificate('call-123456', 'alice');

    expect(certificate.liveURL, 'wss://legacy-rtc.example.test');
    expect(certificate.roomID, 'call-123456');
  });

  for (final legacyURL in <String?>[null, '', ' \t\n ']) {
    test(
        'empty legacy liveURL falls back to serverUrl: ${legacyURL == null ? 'null' : legacyURL.isEmpty ? 'empty' : 'whitespace'}',
        () async {
      adapter.payload = {
        'token': 'rtc-token',
        'liveURL': legacyURL,
        'serverUrl': 'ws://rtc.example.test:7880',
      };

      final certificate = await requestRtcCertificate('call-123456', 'alice');

      expect(certificate.liveURL, 'ws://rtc.example.test:7880');
      expect(certificate.roomID, 'call-123456');
    });
  }

  test('RTC network failure keeps login and returns one compact error',
      () async {
    adapter.networkFailure = true;
    await expectLater(requestRtcCertificate('call-123456', 'alice'),
        throwsA(isA<CallTransportUnavailable>()));
    expect(DataSp.userID, 'alice');
    expect(DataSp.chatToken, 'chat-secret');
    expect(callErrorMessage(const CallTransportUnavailable()),
        StrRes.networkError);
  });

  test('business failure keeps login and is left for the session error handler',
      () async {
    adapter.errCode = 500;
    await expectLater(requestRtcCertificate('call-123456', 'alice'),
        throwsA(isA<(int, String)>()));
    expect(DataSp.userID, 'alice');
    expect(DataSp.chatToken, 'chat-secret');
  });

  test('wrong room or incomplete token cannot be accepted', () async {
    for (final payload in [
      {
        'token': 'rtc-token',
        'liveURL': 'wss://rtc.example.test',
        'roomID': 'different-room'
      },
      {
        'token': 'rtc-token',
        'serverUrl': 'ws://rtc.example.test:7880',
        'roomID': 'different-room'
      },
      {'token': '', 'liveURL': 'wss://rtc.example.test'},
      {'token': '', 'serverUrl': 'ws://rtc.example.test:7880'},
      {'token': ' \t\n ', 'serverUrl': 'ws://rtc.example.test:7880'},
      {'serverUrl': 'ws://rtc.example.test:7880'},
      {'token': 'rtc-token', 'serverUrl': ''},
      {'token': 'rtc-token', 'liveURL': '', 'serverUrl': '  '},
      {'token': 'rtc-token'},
      <String, Object?>{},
      null,
    ]) {
      adapter.payload = payload;
      await expectLater(requestRtcCertificate('call-123456', 'alice'),
          throwsA(isA<InvalidCallCertificate>()));
    }
  });

  test('incorrect certificate field and payload types are rejected', () async {
    for (final payload in <Object?>[
      {'token': 123, 'serverUrl': 'ws://rtc.example.test:7880'},
      {'token': 'rtc-token', 'serverUrl': 123},
      {
        'token': 'rtc-token',
        'liveURL': 123,
        'serverUrl': 'ws://rtc.example.test:7880',
      },
      {
        'token': 'rtc-token',
        'serverUrl': 'ws://rtc.example.test:7880',
        'roomID': 123,
      },
      {
        'token': 'rtc-token',
        'serverUrl': 'ws://rtc.example.test:7880',
        'busyLineUserIDList': 'not-a-list',
      },
      ['not', 'a', 'certificate'],
      'not-a-certificate',
      123,
    ]) {
      adapter.payload = payload;
      await expectLater(requestRtcCertificate('call-123456', 'alice'),
          throwsA(isA<InvalidCallCertificate>()));
    }
  });

  test('invalid call IDs never request RTC credentials', () async {
    for (final room in ['', 'tiny', '../room', 'room with spaces']) {
      await expectLater(requestRtcCertificate(room, 'alice'),
          throwsA(isA<InvalidCallCertificate>()));
    }
    expect(adapter.requests, isEmpty);
  });

  test('busy and permission errors use existing short messages', () {
    expect(callErrorMessage(const CallBusy()), StrRes.busyVideoCallHint);
    expect(callErrorMessage(const CallPermissionDenied('microphone')),
        StrRes.permissionDeniedTitle);
    expect(
        callErrorMessage(PlatformException(
            code: 'NOT_NUMERIC',
            message: List.filled(100, 'diagnostic').join())),
        StrRes.callFail);
  });
}
