import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio client;
  late MomentsApi api;
  late List<RequestOptions> requests;
  dynamic payload;
  var status = 200;
  var token = 'business-token';

  setUp(() {
    requests = [];
    status = 200;
    token = 'business-token';
    payload = {'errCode': 0, 'data': null};
    client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(
          Response(requestOptions: request, statusCode: status, data: payload));
    }));
    api = MomentsApi(
        client: client,
        baseUrl: 'https://business.example/chat/',
        tokenProvider: () => token);
  });
  tearDown(() => client.close(force: true));

  test('privacy commands use IM IDs authenticated PUT and DELETE paths',
      () async {
    const userId = 'im:user/100';
    await api.setBlockedViewer(userId, true);
    await api.setBlockedViewer(userId, false);
    await api.setHiddenAuthor(userId, true);
    await api.setHiddenAuthor(userId, false);
    expect(requests.map((request) => request.method),
        ['PUT', 'DELETE', 'PUT', 'DELETE']);
    expect(requests.map((request) => request.path), [
      'https://business.example/chat/moments/settings/blocked-viewers/im%3Auser%2F100',
      'https://business.example/chat/moments/settings/blocked-viewers/im%3Auser%2F100',
      'https://business.example/chat/moments/settings/hidden-authors/im%3Auser%2F100',
      'https://business.example/chat/moments/settings/hidden-authors/im%3Auser%2F100'
    ]);
    for (final request in requests) {
      expect(request.headers['token'], 'business-token');
      expect(request.headers['operationID'], isA<String>());
      expect((request.headers['operationID'] as String).isNotEmpty, true);
      expect(request.headers['Authorization'], isNull);
      expect(request.data, isNull);
    }
    expect(requests.map((request) => request.headers['operationID']).toSet(),
        hasLength(4));
  });

  test('empty and minimal acknowledgements do not require global settings',
      () async {
    for (final acknowledgement in [
      null,
      <String, dynamic>{},
      {'userID': 'friend', 'removed': true}
    ]) {
      payload = {'errCode': 0, 'data': acknowledgement};
      final blocked = await api.setBlockedViewer('friend', true);
      final hidden = await api.setHiddenAuthor('friend', false);
      expect(blocked.blockedViewersLoaded, false);
      expect(blocked.hiddenAuthorsLoaded, false);
      expect(hidden.blockedViewersLoaded, false);
      expect(hidden.hiddenAuthorsLoaded, false);
    }
    // These are command acknowledgements; no GET/PATCH of global settings occurs.
    expect(requests, hasLength(6));
    expect(
        requests.every((request) =>
            request.path.contains('/blocked-viewers/') ||
            request.path.contains('/hidden-authors/')),
        true);
  });

  test('privacy business errors remain failures instead of empty success',
      () async {
    for (final semantic in ['RELATION_UNAVAILABLE', 'PERMISSION_REVOKED']) {
      payload = {
        'errCode': 20012,
        'errMsg': 'Forbidden',
        'errDlt': semantic,
        'data': null
      };
      for (final command in [
        () => api.setBlockedViewer('friend', true),
        () => api.setHiddenAuthor('friend', false)
      ]) {
        await expectLater(
            command(),
            throwsA(isA<MomentsException>()
                .having((error) => error.code, 'semantic', semantic)));
      }
    }
    payload = {'errCode': 1001, 'errMsg': 'ArgsError', 'data': null};
    await expectLater(
        api.setHiddenAuthor('friend', true),
        throwsA(isA<MomentsException>()
            .having((error) => error.code, 'arguments', 'ArgsError')));
  });

  test('HTTP failure and malformed acknowledgement cannot confirm membership',
      () async {
    status = 503;
    payload = null;
    await expectLater(
        api.setBlockedViewer('friend', true),
        throwsA(isA<MomentsException>()
            .having((error) => error.unknownResult, 'uncertain write', true)));
    status = 200;
    payload = {'errCode': 0, 'data': 'malformed'};
    await expectLater(
        api.setHiddenAuthor('friend', true),
        throwsA(isA<MomentsException>().having(
            (error) => error.unknownResult, 'invalid acknowledgement', true)));
  });

  test('bare HTTP 204 cannot replace the agreed success envelope', () async {
    status = 204;
    payload = null;
    await expectLater(
        api.setBlockedViewer('friend', false),
        throwsA(isA<MomentsException>().having(
            (error) => error.unknownResult, 'missing success envelope', true)));
  });

  test('late acknowledgement after token switch cannot confirm old-account IDs',
      () async {
    client.interceptors.clear();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      token = 'other-account-token';
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'errCode': 0, 'data': null}));
    }));
    await expectLater(
        api.setBlockedViewer('friend', true),
        throwsA(isA<MomentsException>()
            .having((error) => error.authRequired, 'old session', true)));
  });
}
