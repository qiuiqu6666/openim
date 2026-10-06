import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _HTTP implements HttpClientAdapter {
  final reply = Completer<ResponseBody>();
  RequestOptions? request;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    request = options;
    return reply.future;
  }

  void respond(Map<String, dynamic> value) =>
      reply.complete(ResponseBody.fromString(
        jsonEncode(value),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      ));
}

Future<void> _credentials(String account) async {
  OpenIM.iMManager.userID = account;
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': account,
    'chatToken': '$account-chat',
    'imToken': '$account-im',
  }));
}

Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _HTTP adapter;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _credentials('old');
    http.dio = Dio();
    HttpUtil.init();
    adapter = _HTTP();
    http.dio.httpClientAdapter = adapter;
  });
  tearDown(() => http.dio.close(force: true));

  for (final keyword in [
    'abcdefgh12',
    '@abcdefgh12',
    '0012345678',
    '@0012345678',
  ]) {
    test('public account $keyword uses default account search', () async {
      final pending = ContactSearchSource().users(keyword, 2);
      await _flush();
      final request = adapter.request!;
      expect(request.path, Urls.searchUserFullInfo);
      expect(request.data, {
        'pagination': {'pageNumber': 2, 'showNumber': 20},
        'keyword': keyword,
      });
      expect(request.headers['token'], 'old-chat');
      adapter.respond({
        'errCode': 0,
        'data': {
          'users': [
            {'userID': 'im_target', 'account': '@0012345678'}
          ]
        }
      });
      final users = await pending;
      expect(users?.single.userID, 'im_target');
      expect(users?.single.account, '@0012345678');
    });
  }

  for (final entry in [
    (keyword: 'alice@example.com', way: 3),
    (keyword: '18828838848', way: 2),
    (keyword: '+886912345678', way: 2),
    (keyword: '+0012345678', way: 2),
  ]) {
    test('${entry.keyword} preserves its allowed search method', () async {
      final pending = ContactSearchSource().users(entry.keyword, 1);
      await _flush();
      expect(adapter.request?.data, {
        'pagination': {'pageNumber': 1, 'showNumber': 20},
        'keyword': entry.keyword,
        'way': entry.way,
      });
      adapter.respond({
        'errCode': 0,
        'data': {'users': []}
      });
      expect(await pending, isEmpty);
    });
  }

  test('account lookup uses the currently configured server', () async {
    final originalConfig =
        Map<String, String>.from(DataSp.getServerConfig() ?? {});
    final earlierURL = Urls.searchUserFullInfo;
    try {
      await DataSp.putServerConfig(
          {'authUrl': 'https://account-server.example/chat'});
      final pending = ContactSearchSource().users('@abcdefgh12', 1);
      await _flush();
      expect(adapter.request?.path,
          'https://account-server.example/chat/user/search/full');
      expect(adapter.request?.path, isNot(earlierURL));
      expect(adapter.request?.headers['token'], 'old-chat');
      adapter.respond({
        'errCode': 0,
        'data': {'users': []}
      });
      expect(await pending, isEmpty);
    } finally {
      await DataSp.putServerConfig(originalConfig);
    }
  });

  for (final friends in [false, true]) {
    test(
        '${friends ? 'friend' : 'user'} search transports preserve new credentials on an old auth error',
        () async {
      final source = ContactSearchSource();
      final events = <dynamic>[];
      final subscription = Apis.kickoffController.stream.listen(events.add);
      final pending =
          friends ? source.friends('keyword') : source.users('keyword', 2);
      final rejection = expectLater(pending, throwsA(isA<(int, String?)>()));
      await _flush();
      expect(adapter.request?.headers['token'], 'old-chat');
      await _credentials('new');
      adapter.respond({'errCode': 1503, 'errMsg': 'expired', 'data': null});
      await rejection;
      await _flush();
      expect(events, isEmpty);
      expect(DataSp.userID, 'new');
      await subscription.cancel();
    });
  }

  test('transport network failure cannot clear credentials or navigate',
      () async {
    final pending = ContactSearchSource().users('query', 1);
    final rejection = expectLater(
        pending,
        throwsA(isA<DioException>().having(
            (e) => e.type, 'network error', DioExceptionType.connectionError)));
    await _flush();
    adapter.reply.completeError(DioException(
        requestOptions: adapter.request!,
        type: DioExceptionType.connectionError));
    await rejection;
    expect(DataSp.userID, 'old');
  });

  test('current token auth failure still uses the existing interceptor once',
      () async {
    final events = <dynamic>[];
    final subscription = Apis.kickoffController.stream.listen(events.add);
    final pending = ContactSearchSource().friends('query');
    final rejection = expectLater(pending, throwsA(isA<(int, String?)>()));
    await _flush();
    adapter.respond({'errCode': 1506, 'errMsg': 'expired', 'data': null});
    await rejection;
    await _flush();
    expect(events, [1506]);
    await subscription.cancel();
  });
}
