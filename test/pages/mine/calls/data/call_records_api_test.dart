import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/calls/data/call_records_api.dart';
import 'package:openim_common/openim_common.dart';

Map<String, dynamic> _json({String callID = 'call_0001'}) => {
      'callID': callID,
      'mediaType': 'audio',
      'roomType': 'single',
      'direction': 'out',
      'status': 'completed',
      'peerUserID': 'im_peer',
      'groupID': '',
      'duration': 42,
      'startedAt': 1790849179579,
      'endedAt': 1790849221579,
      'updatedAt': 1790849221600,
    };

CallRecords _record() => CallRecordsApi.decodeRecord(_json());

void main() {
  test(
      'uses only captured chat token and exact scalar payload on Chat endpoint',
      () async {
    final client = Dio();
    final requests = <RequestOptions>[];
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'errCode': 0,
        'data': request.method == 'GET'
            ? {
                'records': [_json()],
                'syncAt': 1790849221700
              }
            : _json(),
      }));
    }));
    final api =
        CallRecordsApi(client: client, baseUrl: 'https://chat.test/chat/');
    await api.report(_record()..participantUserIDs = ['im_peer', 'im_peer'],
        token: 'captured-chat-token');
    final page =
        await api.page(syncAt: 12, limit: 200, token: 'captured-chat-token');
    expect(page.records.single.callID, 'call_0001');
    expect(
        requests.every((request) =>
            request.path == 'https://chat.test/chat/call-records' &&
            request.headers['token'] == 'captured-chat-token'),
        isTrue);
    expect(requests.last.queryParameters, {'syncAt': 12, 'limit': 200});
    final expected = _json()..remove('updatedAt');
    expected['participantUserIDs'] = ['im_peer'];
    expect(requests.first.data, expected);
    expect(requests.map((request) => request.headers['operationID']).toSet(),
        hasLength(2));
    client.close(force: true);
  });

  test('zero endedAt is valid and unsuccessful records normalize duration', () {
    final decoded = CallRecordsApi.decodeRecord(_json()
      ..['endedAt'] = 0
      ..['status'] = 'missed');
    expect(decoded.endedAt, 0);
    expect(decoded.duration, 0);
    expect(decoded.success, isFalse);
    for (final malformed in [
      _json(callID: 'short'),
      _json(callID: 'call/bad1'),
      _json()..['duration'] = 86401,
      _json()..['duration'] = -1,
      _json()..['startedAt'] = 1.5,
      _json()..['endedAt'] = 1790849179578,
      _json()..['endedAt'] = 1790849179579 + 86400001,
      _json()..['status'] = 'failed',
      _json()..['direction'] = 'incoming',
      _json()..['peerUserID'] = '',
    ]) {
      expect(
          () => CallRecordsApi.decodeRecord(malformed), throwsFormatException);
    }
  });

  test(
      'report strips legacy terminal names and does not send noncompleted duration',
      () async {
    final client = Dio();
    Map? payload;
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      payload = request.data as Map;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'errCode': 0,
        'data': {...payload!, 'updatedAt': 50},
      }));
    }));
    final local = _record()
      ..state = 'rejected'
      ..success = false
      ..duration = 24;
    await CallRecordsApi(client: client).report(local, token: 'chat-token');
    expect(payload!['status'], 'rejected');
    expect(payload!['duration'], 0);
    client.close(force: true);
  });

  test('rejects invalid pagination and more than 100 participants before HTTP',
      () async {
    final client = Dio();
    final api = CallRecordsApi(client: client);
    await expectLater(
        api.page(syncAt: -1, token: 'token'), throwsArgumentError);
    await expectLater(
        api.page(syncAt: 0, limit: 501, token: 'token'), throwsArgumentError);
    await expectLater(
        api.report(
            _record()
              ..participantUserIDs = List.generate(101, (index) => 'im_$index'),
            token: 'token'),
        throwsArgumentError);
    client.close(force: true);
  });

  test('same call ID cannot acknowledge a different peer, direction or room',
      () async {
    final client = Dio();
    Map<String, dynamic> response = _json();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'errCode': 0, 'data': response}));
    }));
    final api = CallRecordsApi(client: client);
    for (final changed in [
      _json()..['peerUserID'] = 'im_other',
      _json()..['direction'] = 'in',
      _json()
        ..['roomType'] = 'group'
        ..['groupID'] = 'group_other',
      _json(callID: 'call_other'),
    ]) {
      response = changed;
      await expectLater(
          api.report(_record(), token: 'token'), throwsFormatException);
    }
    client.close(force: true);
  });

  test('business failures never expose raw upstream debugging details',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'errCode': 29999,
        'errDlt': 'goroutine /tmp/private trace',
        'data': {},
      }));
    }));
    await expectLater(
        CallRecordsApi(client: client).page(syncAt: 0, token: 'token'),
        throwsA(isA<CallRecordsException>()
            .having((error) => error.code, 'code', 29999)
            .having((error) => error.message, 'message',
                isNot(contains('/tmp/private')))));
    client.close(force: true);
  });
}
