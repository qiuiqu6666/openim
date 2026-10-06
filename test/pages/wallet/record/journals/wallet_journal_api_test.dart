import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/data/wallet_session_source.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_query.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_error.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_source.dart';
import 'package:openim/services/fund_api.dart';

import '../../data/wallet_fund_test_transport.dart';
import 'wallet_journal_entry_test.dart' show journalTestJson;

Map<String, dynamic> _journalPage() => {
      'items': [journalTestJson(id: 'event-2'), journalTestJson(id: 'event-1')],
      'limit': 20,
      'hasMore': true,
      'nextCursor': 'cursor+/=opaque',
    };

void main() {
  late WalletFundTestTransport transport;
  setUp(() => transport = WalletFundTestTransport());
  tearDown(() => transport.close());

  test('journals use authenticated Chat GET and a unique ID for every cursor',
      () async {
    transport.respond(_journalPage());
    const query = WalletJournalQuery(
      currency: 'USDT',
      bizType: 'packet_normal',
      type: 'packet_refund',
      direction: 'unfreeze',
      startTime: 1791216000000,
      endTime: 1791302400000,
    );
    final first = await transport.wallet.fetchJournals(query);
    transport.respond({
      ..._journalPage(),
      'items': [journalTestJson(id: 'event-0')],
      'hasMore': false,
      'nextCursor': '',
    });
    final second = await transport.wallet
        .fetchJournals(query.withCursor(first.nextCursor));
    expect(first.items.map((item) => item.id), ['event-2', 'event-1']);
    expect(first.items.map((item) => item.orderID),
        ['packet-order', 'packet-order']);
    expect(second.items.single.id, 'event-0');
    for (final request in transport.requests) {
      expect(request.path, 'https://chat.example.test/chat/fund/journals');
      expect(request.method, 'GET');
      expect(request.headers['token'], 'chat-token');
      expect(request.data, isNull);
      expect(
          request.queryParameters.keys,
          isNot(anyOf(contains('userID'), contains('page'),
              contains('pageSize'), contains('offset'))));
      expect(request.queryParameters['currency'], 'USDT');
      expect(request.queryParameters['startTime'], 1791216000000);
      expect(request.queryParameters['endTime'], 1791302400000);
      expect(request.queryParameters['direction'], 'unfreeze');
      expect(request.queryParameters['type'], 'packet_refund');
      expect(request.queryParameters['bizType'], 'packet_normal');
      expect(request.queryParameters['limit'], 20);
      expect(
          request.headers['operationID'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    }
    expect(transport.requests.first.queryParameters.containsKey('cursor'),
        isFalse);
    expect(
        transport.requests.last.queryParameters['cursor'], 'cursor+/=opaque');
    expect(
        transport.requests
            .map((request) => request.headers['operationID'])
            .toSet(),
        hasLength(2));
    expect(first.items.first.beforeAvailable, isNull);
  });

  test('default journal read omits all filters, and BI99 is sent as wire code',
      () async {
    transport.respond(
        {..._journalPage(), 'items': [], 'hasMore': false, 'nextCursor': ''});
    await transport.wallet.fetchJournals(const WalletJournalQuery());
    await transport.wallet
        .fetchJournals(const WalletJournalQuery(currency: 'BI99', limit: 100));
    expect(transport.requests.first.queryParameters, {'limit': 20});
    expect(transport.requests.last.queryParameters,
        {'currency': 'BI99', 'limit': 100});
  });

  test('invalid query and missing Chat authentication never send a request',
      () async {
    await expectLater(
        transport.wallet.fetchJournals(const WalletJournalQuery(limit: 101)),
        throwsFormatException);
    transport.token = null;
    await expectLater(
        transport.wallet.fetchJournals(const WalletJournalQuery()),
        throwsA(
            isA<FundApiException>().having((error) => error.code, 'code', -2)));
    expect(transport.requests, isEmpty);
  });

  test('parameter, auth, service and malformed responses surface safe failures',
      () async {
    transport.body = {
      'errCode': 1001,
      'errMsg': 'raw private diagnostics',
      'data': {}
    };
    await expectLater(
        transport.wallet.fetchJournals(const WalletJournalQuery()),
        throwsA(isA<FundApiException>()
            .having((error) => error.code, 'code', 1001)
            .having((error) => error.message, 'message', '资金请求失败')));
    for (final status in [401, 503]) {
      transport.statusCode = status;
      transport.failure = DioExceptionType.badResponse;
      await expectLater(
          transport.wallet.fetchJournals(const WalletJournalQuery()),
          throwsA(isA<FundApiException>().having(
              (error) => error.code, 'code', status == 503 ? 500 : 401)));
    }
    transport.statusCode = 200;
    transport.failure = null;
    transport.respond({..._journalPage(), 'nextCursor': ''});
    await expectLater(
        transport.wallet.fetchJournals(const WalletJournalQuery()),
        throwsFormatException);
    transport.respond({
      ..._journalPage(),
      'items': [journalTestJson()..['assetDelta'] = '-8']
    });
    await expectLater(
        transport.wallet.fetchJournals(const WalletJournalQuery()),
        throwsFormatException);
  });

  test('journal errors explain query parameters rather than payment recipients',
      () {
    expect(
        walletJournalErrorMessage(
            const FundApiException(1001, 'raw diagnostics')),
        '资金明细查询参数无效，请检查筛选条件后重试');
    expect(
        walletJournalErrorMessage(
            const FundApiException(401, 'raw diagnostics')),
        '登录状态已失效，请重新登录');
    expect(
        walletJournalErrorMessage(
            const FormatException('Invalid journal page')),
        '资金数据异常，请稍后重试');
  });

  test(
      'journal source rejects a late prior-account page and sends no next read',
      () async {
    var owner = 'server:old-owner';
    final arrived = Completer<void>();
    final pending = Completer<Map<String, dynamic>>();
    final client = Dio();
    var requestCount = 0;
    client.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      requestCount++;
      arrived.complete();
      handler.resolve(Response<dynamic>(
          requestOptions: request,
          statusCode: 200,
          data: {'errCode': 0, 'data': await pending.future}));
    }));
    addTearDown(() => client.close(force: true));
    final repository = WalletFundRepository(
      accountProvider: () => owner,
      api: WalletFundApi(
          api: FundApi(
              client: client,
              baseUrl: 'https://chat.example.test',
              tokenProvider: () => 'synthetic-token')),
    );
    expect(repository, isA<WalletJournalSource>());
    final result = repository.getJournalPage(const WalletJournalQuery());
    final rejected =
        expectLater(result, throwsA(isA<WalletAccountChangedException>()));
    await arrived.future;
    owner = 'server:new-owner';
    pending.complete({..._journalPage(), 'hasMore': false, 'nextCursor': ''});
    await rejected;
    await expectLater(
        repository
            .getJournalPage(const WalletJournalQuery(cursor: 'old-cursor')),
        throwsA(isA<WalletAccountChangedException>()));
    expect(requestCount, 1);
  });
}
