import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';

void main() {
  test(
      'Chat API sends chat token, unique operation IDs and version without owner ID',
      () async {
    final client = Dio();
    final requests = <RequestOptions>[];
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'errCode': 0,
        'data': request.method == 'GET'
            ? {'stars': [], 'syncAt': 20}
            : {
                'friendUserID': 'friend',
                'starred': true,
                'version': 1,
                'updatedAt': 10
              },
      }));
    }));
    final api = StarFriendApi(client: client);
    await api.set('friend', true, 0, 'chat-token');
    await api.page(10, 'chat-token');
    expect(requests.first.data, {'starred': true, 'version': 0});
    expect(requests.first.path, endsWith('/chat/star-friends/friend'));
    expect(requests.last.queryParameters, {'updatedAfter': 10, 'limit': 500});
    expect(requests.map((r) => r.headers['operationID']).toSet().length, 2);
    expect(requests.every((r) => r.headers['token'] == 'chat-token'), true);
  });
  test('HTTP 200 conflict is handled as conflict, not success', () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'errCode': 20016,
        'data': {
          'friendUserID': 'friend',
          'starred': false,
          'version': 2,
          'updatedAt': 20
        },
      }));
    }));
    await expectLater(
        StarFriendApi(client: client).set('friend', true, 0, 'token'),
        throwsA(isA<StarFriendConflict>()
            .having((e) => e.current.version, 'version', 2)));
  });
}
