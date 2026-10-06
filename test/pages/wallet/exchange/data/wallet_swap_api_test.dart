import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/services/fund_api.dart';

import '../../data/wallet_fund_test_transport.dart';
import 'wallet_swap_quote_test.dart' show quoteFixture;

void main() {
  late WalletFundTestTransport transport;
  setUp(() => transport = WalletFundTestTransport());
  tearDown(() => transport.close());

  Future<WalletSwapQuote> quote() => transport.wallet.fetchSwapQuote(
      amount: FundAmount.parse('10.000000', FundCurrency.usdt),
      toCurrency: FundCurrency.trx);

  Future<WalletSwapResult> swap({String? quoteID = 'sq-test-1'}) =>
      transport.wallet.swap(
          clientOrderID: 'client-1',
          amount: FundAmount.parse('10', FundCurrency.usdt),
          toCurrency: FundCurrency.trx,
          payPassword: '123456',
          quoteID: quoteID);

  Map<String, dynamic> completedSwap() => {
        'order': walletTestOrder(biz: 'swap', status: 'done')
          ..addAll({
            'quoteID': 'sq-test-1',
            'targetCurrency': 'TRX',
            'targetAmount': '29',
          }),
        'received': '29',
      };

  test('preview posts only exact input with Chat auth and no password',
      () async {
    transport.respond(quoteFixture());
    expect((await quote()).estimatedReceived.decimal, '29');
    await quote();
    for (final request in transport.requests) {
      expect(request.path, endsWith('/chat/fund/swap-quotes'));
      expect(request.method, 'POST');
      expect(request.contentType, Headers.jsonContentType);
      expect(request.headers['token'], 'chat-token');
      expect(request.data, {
        'fromCurrency': 'USDT',
        'toCurrency': 'TRX',
        'amount': '10',
      });
      expect(request.queryParameters, isEmpty);
    }
    expect(transport.requests[0].headers['operationID'],
        isNot(transport.requests[1].headers['operationID']));
  });

  test('mismatched quote input is rejected before the user can submit',
      () async {
    for (final changes in [
      {'amount': '20', 'estimatedReceived': '58'},
      {'fromCurrency': 'BI99'},
      {'toCurrency': 'BI99'},
    ]) {
      transport.respond(quoteFixture()..addAll(changes));
      await expectLater(quote(), throwsFormatException);
    }
    expect(transport.requests, hasLength(3));
    expect(
        transport.requests.every((r) => r.path.endsWith('swap-quotes')), true);
  });

  test('invalid preview inputs never contact the service', () async {
    for (final amount in ['0', '9223372036854.775808']) {
      await expectLater(
          transport.wallet.fetchSwapQuote(
              amount: FundAmount.parse(amount, FundCurrency.usdt),
              toCurrency: FundCurrency.trx),
          throwsFormatException);
    }
    await expectLater(
        transport.wallet.fetchSwapQuote(
            amount: FundAmount.parse('1', FundCurrency.trx),
            toCurrency: FundCurrency.trx),
        throwsFormatException);
    expect(transport.requests, isEmpty);
  });

  test('quote failures are read failures and never report a possible debit',
      () async {
    transport.failure = DioExceptionType.receiveTimeout;
    await expectLater(
        quote(),
        throwsA(isA<FundApiException>()
            .having((e) => e.isUncertain, 'quote mutation', false)));
    transport.failure = null;
    for (final code in [500, 20030, 20075]) {
      transport.body = {'errCode': code, 'errMsg': 'secret 123456'};
      await expectLater(
          quote(),
          throwsA(isA<FundApiException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.isUncertain, 'quote mutation', false)
              .having((e) => e.toString(), 'safe error',
                  isNot(contains('123456')))));
    }
  });

  test('new swaps carry the exact quote ID and legacy calls omit it', () async {
    transport.respond(completedSwap());
    expect((await swap()).order.quoteID, 'sq-test-1');
    expect(transport.requests.last.data, {
      'clientOrderID': 'client-1',
      'fromCurrency': 'USDT',
      'toCurrency': 'TRX',
      'amount': '10',
      'payPassword': '123456',
      'quoteID': 'sq-test-1',
    });
    final legacy = completedSwap();
    (legacy['order'] as Map).remove('quoteID');
    transport.respond(legacy);
    expect((await swap(quoteID: null)).order.quoteID, null);
    expect((transport.requests.last.data as Map).containsKey('quoteID'), false);
  });

  test('missing or conflicting quote IDs retain a real order for recovery',
      () async {
    for (final id in <Object?>[null, '', 'sq-other', ' sq-test-1 ', 42]) {
      final data = completedSwap();
      (data['order'] as Map)['quoteID'] = id;
      transport.respond(data);
      await expectLater(
          swap(),
          throwsA(isA<FundApiException>()
              .having((e) => e.isUncertain, 'uncertain success', true)
              .having((e) => e.orderID, 'real service ID', 'order-1')));
    }
  });

  test('invalid quote IDs and overlong client IDs never submit', () async {
    for (final id in ['', ' sq-test-1', 'sq test']) {
      await expectLater(swap(quoteID: id), throwsFormatException);
    }
    await expectLater(
        transport.wallet.swap(
            clientOrderID: 'x' * 129,
            amount: FundAmount.parse('1', FundCurrency.usdt),
            toCurrency: FundCurrency.trx,
            payPassword: '123456',
            quoteID: 'sq-test-1'),
        throwsFormatException);
    expect(transport.requests, isEmpty);
  });

  test(
      'by-client recovery safely encodes arbitrary path characters in the query',
      () async {
    const id = 'swap/1?x=中文&quote=2';
    transport.respond(completedSwap());
    (transport.body['data']['order'] as Map)['clientOrderID'] = id;
    final order = await transport.wallet.getOrderByClient(id);
    expect(order.clientOrderID, id);
    final request = transport.requests.single;
    expect(request.path, endsWith('/chat/fund/orders/by-client'));
    expect(request.method, 'GET');
    expect(request.data, null);
    expect(request.queryParameters, {'clientOrderID': id});
    expect(request.uri.queryParameters, {'clientOrderID': id});
    expect(request.uri.path, '/chat/fund/orders/by-client');
  });

  test('by-client recovery requires an exact owned client order ID', () async {
    for (final id in ['', 'other', null]) {
      final data = completedSwap();
      (data['order'] as Map)['clientOrderID'] = id;
      transport.respond(data);
      await expectLater(
          transport.wallet.getOrderByClient('client-1'), throwsFormatException);
    }
    await expectLater(
        transport.wallet.getOrderByClient('x' * 129), throwsFormatException);
    expect(transport.requests, hasLength(3));
  });

  test(
      'server errors and consumed or conflicting quotes require swap recovery only',
      () async {
    for (final code in [500, 503, 20062, 20073]) {
      transport.body = {'errCode': code, 'errMsg': 'secret 123456'};
      await expectLater(
          swap(),
          throwsA(isA<FundApiException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.isUncertain, 'restore original swap', true)));
      await expectLater(
          transport.wallet.withdraw(
              clientOrderID: 'client-1',
              amount: FundAmount.parse('10', FundCurrency.usdt),
              toAddress: 'T-destination',
              payPassword: '123456'),
          throwsA(isA<FundApiException>().having(
              (e) => e.isUncertain, 'existing withdrawal behavior', false)));
    }
    for (final code in [20026, 20027, 20072, 20074, 20075]) {
      transport.body = {'errCode': code};
      await expectLater(
          swap(),
          throwsA(isA<FundApiException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.isUncertain, 'explicitly prevented new swap',
                  false)));
    }
  });
}
