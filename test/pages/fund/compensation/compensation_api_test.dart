import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim/pages/fund/compensation/data/compensation_api.dart';
import 'support.dart';

void main() {
  test('authenticated endpoint contract uses campaign ID, never client amounts',
      () async {
    final dio = Dio();
    addTearDown(dio.close);
    final paths = <String>[];
    bool valid = true;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      paths.add(r.path);
      expect(r.headers['token'], 'test-token');
      expect(r.headers['operationID'], isNotEmpty);
      expect(r.method, 'POST');
      expect(r.data, paths.length == 1 ? {} : {'id': 'activity-one'});
      h.resolve(Response(requestOptions: r, data: {
        'errCode': 0,
        'data': paths.length == 1
            ? {'activity': null, 'serverTime': '2026-10-17T12:00:00Z'}
            : response(state: paths.length == 3 ? 'claimed' : 'unclaimed')
      }));
    }));
    final api = CompensationApi(
        transport: FundApi(
            client: dio,
            baseUrl: 'https://example.invalid',
            tokenProvider: () => 'test-token'),
        sessionCheck: () => valid);
    expect(await api.entry(), isNull);
    await api.detail('activity-one');
    expect((await api.claim('activity-one')).amount, '88.66');
    expect(paths.map((p) => Uri.parse(p).path), [
      '/chat/fund/compensation/entry',
      '/chat/fund/compensation/detail',
      '/chat/fund/compensation/claim'
    ]);
    valid = false;
    await expectLater(
        api.claim('activity-one'), throwsA(isA<FundApiException>()));
    expect(paths.length, 3);
  });
  test('account changed during response cannot reveal result', () async {
    final dio = Dio();
    addTearDown(dio.close);
    var valid = true;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      valid = false;
      h.resolve(Response(
          requestOptions: r,
          data: {'errCode': 0, 'data': response(state: 'claimed')}));
    }));
    final api = CompensationApi(
        transport: FundApi(
            client: dio,
            baseUrl: 'https://example.invalid',
            tokenProvider: () => 'token'),
        sessionCheck: () => valid);
    await expectLater(
        api.detail('activity-one'), throwsA(isA<FundApiException>()));
  });
}
