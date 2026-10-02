import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/platform_config_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? request;
  Map<String, dynamic> body = {
    'errCode': 0,
    'data': {
      'officialURL': 'https://example.com',
      'email': 'support@example.com',
      'android': {
        'latestVersion': '3.10.0',
        'downloadURL': 'https://example.com/download',
        'downloadLink': 'https://example.com/app.apk',
        'grayRatio': 30
      },
      'ios': {'latestVersion': '4.0.0'}
    }
  };
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  test(
      'public GET sends operation ID, parses per-platform nested configuration',
      () async {
    final adapter = _Adapter();
    final client = Dio()..httpClientAdapter = adapter;
    final config = await PlatformConfigService.fetch(client: client);
    expect(adapter.request!.method, 'GET');
    expect(adapter.request!.path, endsWith('/chat/platform'));
    expect(adapter.request!.headers['operationID'], isNotEmpty);
    expect(adapter.request!.headers.containsKey('token'), false);
    expect(config.officialURL, 'https://example.com');
    expect(config.email, 'support@example.com');
    expect(config.android.latest, '3.10.0');
    expect(config.android.shareURL, 'https://example.com/download');
    expect(config.android.installURL, 'https://example.com/app.apk');
    expect(config.ios.latest, '4.0.0');
  });
  test('empty configuration and failed response are distinct', () async {
    expect(PlatformConfig({}).android.latest, isEmpty);
    final adapter = _Adapter()..body = {'errCode': 1001, 'data': {}};
    await expectLater(
        PlatformConfigService.fetch(client: Dio()..httpClientAdapter = adapter),
        throwsStateError);
  });
  test('numeric versions do not confuse 3.10 and 3.9', () {
    expect(compareAppVersions('v3.10.0', '3.9.9'), greaterThan(0));
    expect(compareAppVersions('3.8.3+12', '3.8.3'), 0);
    expect(compareAppVersions('3.8', '3.8.0'), 0);
    expect(compareAppVersions('3.8.3', '4.0'), lessThan(0));
  });
}
