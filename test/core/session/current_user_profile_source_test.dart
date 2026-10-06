import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/current_user_profile_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _ProfileTransport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  List<Map<String, Object?>> users = [];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'data': {'users': users},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ProfileTransport transport;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    http.dio = Dio();
    HttpUtil.init();
    transport = _ProfileTransport();
    http.dio.httpClientAdapter = transport;
  });
  tearDown(() => http.dio.close(force: true));

  test('profile privileges require an explicit JSON boolean', () {
    expect(UserFullInfo().isPrivileged, isFalse);
    for (final value in [null, false, 1, 0, 'true', 'false', {}, []]) {
      final profile = UserFullInfo.fromJson({
        'userID': 'me',
        'isPrivileged': value,
        'level': 10,
        'role': 'owner',
      });
      expect(profile.isPrivileged, isFalse, reason: 'value=$value');
      expect(profile.toJson()['isPrivileged'], isFalse);
    }
    final allowed = UserFullInfo.fromJson({
      'userID': 'me',
      'isPrivileged': true,
    });
    expect(allowed.isPrivileged, isTrue);
    expect(UserFullInfo.fromJson(allowed.toJson()).isPrivileged, isTrue);
    expect(UserFullInfo.fromJson({'userID': 'me'}).isPrivileged, isFalse);
  });

  test('an empty account or Chat token never sends a full-profile request',
      () async {
    final source = CurrentUserProfileSource();
    expect(await source.fetch('', 'token'), isNull);
    expect(await source.fetch('   ', 'token'), isNull);
    expect(await source.fetch('me', null), isNull);
    expect(await source.fetch('me', ''), isNull);
    expect(await source.fetch('me', '  '), isNull);
    expect(await source.fetch('me', 'token', baseUrl: ''), isNull);
    expect(transport.requests, isEmpty);
  });

  test('only an exact own-profile identity is returned from the formal API',
      () async {
    transport.users = [
      {'userID': 'another', 'isPrivileged': true},
      {'userID': 'me', 'account': 'public01', 'isPrivileged': false},
    ];
    final profile = await CurrentUserProfileSource()
        .fetch('me', 'chat-token', baseUrl: 'https://profile.example/chat/');
    expect(profile?.userID, 'me');
    expect(profile?.account, 'public01');
    expect(profile?.isPrivileged, isFalse);
    final request = transport.requests.single;
    expect(
        request.uri.toString(), 'https://profile.example/chat/user/find/full');
    expect(request.headers['token'], 'chat-token');
    expect((request.data as Map)['userIDs'], ['me']);
    transport.users = [
      {'userID': 'another', 'isPrivileged': true},
      {'account': 'me', 'isPrivileged': true},
    ];
    expect(await CurrentUserProfileSource().fetch('me', 'chat-token'), isNull);
  });

  test('full-profile URL is resolved again after a configured server change',
      () async {
    transport.users = [
      {'userID': 'me', 'isPrivileged': true},
    ];
    final source = CurrentUserProfileSource();
    await DataSp.putServerConfig({'authUrl': 'https://first.example/chat'});
    expect((await source.fetch('me', 'first-token'))?.isPrivileged, isTrue);
    await DataSp.putServerConfig({'authUrl': 'https://second.example/chat/'});
    expect((await source.fetch('me', 'second-token'))?.isPrivileged, isTrue);
    expect(transport.requests.map((request) => request.uri.toString()), [
      'https://first.example/chat/user/find/full',
      'https://second.example/chat/user/find/full',
    ]);
    expect(transport.requests.last.headers['token'], 'second-token');
  });
}
