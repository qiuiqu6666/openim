import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/services/fund_api.dart';

import 'wallet_fund_test_transport.dart';

void main() {
  late WalletFundTestTransport transport;
  setUp(() => transport = WalletFundTestTransport());
  tearDown(() => transport.close());

  Future<WalletWithdrawResult> withdraw() => transport.wallet.withdraw(
      clientOrderID: 'client-1',
      amount: FundAmount.parse('10', FundCurrency.usdt),
      toAddress: 'T-destination',
      payPassword: '123456');

  Future<WalletSwapResult> swap() => transport.wallet.swap(
      clientOrderID: 'client-1',
      amount: FundAmount.parse('10', FundCurrency.usdt),
      toCurrency: FundCurrency.bi99,
      payPassword: '123456');

  Matcher uncertain() => throwsA(isA<FundApiException>()
      .having((error) => error.isUncertain, 'uncertain outcome', true));

  test('wallet reads reuse Chat authentication and unique operation IDs',
      () async {
    transport.respond({
      'balances': FundCurrency.values
          .map((currency) => {
                'currency': currency.code,
                'available': currency == FundCurrency.usdt ? '-0.000001' : '0',
                'frozen': '0',
              })
          .toList(),
    });
    final balances = await transport.wallet.fetchBalances();
    expect(balances.first.available.decimal, '-0.000001');
    expect(balances.first.available.units, -BigInt.one);
    transport.respond(walletTestAddress());
    final address = await transport.wallet.fetchDepositAddress();
    expect(address.address, 'T-deposit');
    expect(address.usdtContract, 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
    transport.respond({'deposits': <dynamic>[]});
    expect(await transport.wallet.fetchDeposits(), isEmpty);
    expect(transport.requests.map((request) => request.path), [
      'https://chat.example.test/chat/fund/balances',
      'https://chat.example.test/chat/fund/deposit-address',
      'https://chat.example.test/chat/fund/deposits',
    ]);
    for (final request in transport.requests) {
      expect(request.method, 'GET');
      expect(request.headers['token'], 'chat-token');
      expect(request.data, isNull);
      expect(request.queryParameters, isEmpty);
      expect(
          request.headers['operationID'],
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    }
    expect(
        transport.requests
            .map((request) => request.headers['operationID'])
            .toSet(),
        hasLength(3));
  });

  test('pending deposit address stays pending and currencies are immutable',
      () async {
    transport.respond(
        walletTestAddress()..addAll({'status': 'pending', 'address': ''}));
    final address = await transport.wallet.fetchDepositAddress();
    expect(address.isReady, false);
    expect(address.address, isEmpty);
    expect(address.network, 'TRON');
    expect(address.confirmations, 1);
    expect(address.currencies, [FundCurrency.usdt, FundCurrency.trx]);
    expect(() => address.currencies.add(FundCurrency.bi99),
        throwsUnsupportedError);
  });

  test(
      'duplicate tx events retain input order, precision and optional confirmations',
      () async {
    transport.respond({
      'deposits': [
        walletTestDeposit(),
        walletTestDeposit()
          ..addAll({'amount': '9223372036854.775807', 'status': 'orphaned'}),
        walletTestDeposit(txID: 'tx-2')..remove('confirmations'),
      ]
    });
    final records = await transport.wallet.fetchDeposits();
    expect(records.map((record) => record.txID), ['tx-1', 'tx-1', 'tx-2']);
    expect(records.map((record) => record.occurrenceIndex), [0, 1, 0]);
    expect(records[1].amount, '9223372036854.775807');
    expect(records[1].status, 'orphaned');
    expect(records.last.confirmations, null);
    expect(() => records.clear(), throwsUnsupportedError);
    final refreshed = await transport.wallet.fetchDeposits();
    expect(refreshed.map((record) => record.occurrenceIndex), [0, 1, 0]);
  });

  test('withdrawal sends exact wire units and exposes only the real fee',
      () async {
    transport.respond({
      'order': walletTestOrder()..['createdAt'] = 1791032141597,
      'fee': '1.234567'
    });
    final result = await withdraw();
    expect(result.fee, '1.234567');
    expect(result.order.status, 'withdraw_done');
    expect(result.order.toAddress, 'T-destination');
    expect(result.order.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1791032141597, isUtc: true));
    final request = transport.requests.single;
    expect(request.path, endsWith('/chat/fund/withdrawals'));
    expect(request.method, 'POST');
    expect(request.contentType, Headers.jsonContentType);
    expect(request.data, {
      'clientOrderID': 'client-1',
      'mode': 'chain',
      'network': 'TRON',
      'currency': 'USDT',
      'amount': '10',
      'toAddress': 'T-destination',
      'payPassword': '123456',
    });
  });

  test('TRX withdrawals are supported without USDT-only assumptions', () async {
    transport.respond({
      'order': walletTestOrder(currency: 'TRX', amount: '0.000001'),
      'fee': '1.234567'
    });
    final result = await transport.wallet.withdraw(
        clientOrderID: 'client-1',
        amount: FundAmount.parse('0.000001', FundCurrency.trx),
        toAddress: 'T-destination',
        payPassword: '123456');
    expect(result.order.currency, FundCurrency.trx);
    expect(transport.requests.single.data['amount'], '0.000001');
  });

  test('chain withdrawal sends the verification proof with the frozen request',
      () async {
    transport.respond({'order': walletTestOrder(), 'fee': '1.234567'});
    await transport.wallet.withdraw(
        clientOrderID: 'client-1',
        amount: FundAmount.parse('10', FundCurrency.usdt),
        toAddress: 'T-destination',
        payPassword: '123456',
        verifyChallengeID: 'proof-1',
        verifyCode: '246810');
    expect(transport.requests.single.data['mode'], 'chain');
    expect(transport.requests.single.data['network'], 'TRON');
    expect(transport.requests.single.data['verifyChallengeID'], 'proof-1');
    expect(transport.requests.single.data['verifyCode'], '246810');
    transport.requests.clear();
    await expectLater(
        transport.wallet.withdraw(
            clientOrderID: 'client-1',
            amount: FundAmount.parse('10', FundCurrency.usdt),
            toAddress: 'T-destination',
            payPassword: '123456',
            verifyChallengeID: 'proof-1'),
        throwsFormatException);
    expect(transport.requests, isEmpty);
  });

  test(
      'withdrawal ID conflict and service failures require original-ID recovery',
      () async {
    for (final code in [500, 503, 20062]) {
      transport.body = {'errCode': code, 'errMsg': 'private diagnostics'};
      await expectLater(
          withdraw(),
          throwsA(isA<FundApiException>()
              .having((error) => error.code, 'code', code)
              .having((error) => error.isUncertain, 'uncertain', true)));
    }
    expect(transport.requests, hasLength(3));
    expect(transport.requests.map((request) => request.data['clientOrderID']),
        everyElement('client-1'));
  });

  test('manual review order metadata and zero timestamps survive parsing',
      () async {
    transport.respond({
      'order': walletTestOrder(status: 'withdraw_approved')
        ..addAll({
          'scene': 'chain',
          'network': 'TRON',
          'senderID': 'sender',
          'recvID': '',
          'recipientType': '',
          'recipient': '',
          'recipientAreaCode': '',
          'chainTxID': 'a' * 64,
          'fromAddress': 'real-source',
          'reviewedBy': 'reviewer',
          'reviewReason': '审核通过',
          'reviewedAt': 1791252000000,
          'completedBy': '',
          'completionReason': '',
          'completedAt': 0,
        })
    });
    final order = await transport.wallet.getOrder('order-1');
    expect(order.status, 'withdraw_approved');
    expect(order.scene, 'chain');
    expect(order.network, 'TRON');
    expect(order.chainTxID, 'a' * 64);
    expect(order.fromAddress, 'real-source');
    expect(order.reviewedBy, 'reviewer');
    expect(order.reviewReason, '审核通过');
    expect(order.reviewedAt,
        DateTime.fromMillisecondsSinceEpoch(1791252000000, isUtc: true));
    expect(order.completedAt, null);
    expect(order.completedBy, isEmpty);
    expect(order.recipient, isEmpty);
  });

  test(
      'all documented distinct currency pairs use swaps and server received amount',
      () async {
    for (final from in FundCurrency.values) {
      for (final to
          in FundCurrency.values.where((currency) => currency != from)) {
        final received = to == FundCurrency.bi99 ? '1.23' : '1.234567';
        transport.respond({
          'order': walletTestOrder(
              biz: 'swap', status: 'done', currency: from.code, amount: '0.01')
            ..addAll({
              'targetCurrency': to.code,
              'targetAmount': received,
            }),
          'received': received
        });
        final result = await transport.wallet.swap(
            clientOrderID: 'client-1',
            amount: FundAmount.parse('0.01', from),
            toCurrency: to,
            payPassword: '123456');
        expect(result.received, received);
        expect(transport.requests.last.data['fromCurrency'], from.code);
        expect(transport.requests.last.data['toCurrency'], to.code);
      }
    }
  });

  test('swap request uses backend currency codes and no local quote', () async {
    transport.respond({
      'order': walletTestOrder(biz: 'swap', status: 'done')
        ..addAll({'targetCurrency': 'BI99', 'targetAmount': '123.45'}),
      'received': '123.45'
    });
    final result = await swap();
    expect(result.received, '123.45');
    expect(result.order.targetCurrency, FundCurrency.bi99);
    expect(transport.requests.single.data, {
      'clientOrderID': 'client-1',
      'fromCurrency': 'USDT',
      'toCurrency': 'BI99',
      'amount': '10',
      'payPassword': '123456',
    });
    expect(transport.requests.single.path, endsWith('/chat/fund/swaps'));
  });

  test('invalid local withdrawals and swaps never reach the transport',
      () async {
    for (final currency in [FundCurrency.usdt, FundCurrency.bi99]) {
      await expectLater(
          transport.wallet.withdraw(
              clientOrderID: 'client-1',
              amount: FundAmount.parse('0', currency),
              toAddress: 'T-destination',
              payPassword: '123456'),
          throwsFormatException);
    }
    await expectLater(
        transport.wallet.withdraw(
            clientOrderID: 'client-1',
            amount: FundAmount.parse('1', FundCurrency.bi99),
            toAddress: 'T-destination',
            payPassword: '123456'),
        throwsFormatException);
    await expectLater(
        transport.wallet.withdraw(
            clientOrderID: 'client-1',
            amount: FundAmount.parse('9223372036854.775808', FundCurrency.usdt),
            toAddress: 'T-destination',
            payPassword: '123456'),
        throwsFormatException);
    await expectLater(
        transport.wallet.withdraw(
            clientOrderID: 'client-1',
            amount: FundAmount.parse('1', FundCurrency.usdt),
            toAddress: '',
            payPassword: '123456'),
        throwsFormatException);
    await expectLater(
        transport.wallet.swap(
            clientOrderID: 'client-1',
            amount: FundAmount.parse('1', FundCurrency.usdt),
            toCurrency: FundCurrency.usdt,
            payPassword: '123456'),
        throwsFormatException);
    await expectLater(
        transport.wallet.swap(
            clientOrderID: ' client-1 ',
            amount: FundAmount.parse('1', FundCurrency.usdt),
            toCurrency: FundCurrency.trx,
            payPassword: '123456'),
        throwsFormatException);
    await expectLater(
        transport.wallet.swap(
            clientOrderID: 'client-1',
            amount: FundAmount.parse('1', FundCurrency.usdt),
            toCurrency: FundCurrency.trx,
            payPassword: '12345'),
        throwsFormatException);
    expect(transport.requests, isEmpty);
  });

  test(
      'known order GET accepts wallet states and never manufactures absent fields',
      () async {
    for (final status in [
      'withdraw_pending',
      'withdraw_approved',
      'withdraw_done',
      'withdraw_failed'
    ]) {
      transport.respond({
        'order': walletTestOrder(status: status)
          ..remove('fee')
          ..remove('toAddress')
      });
      final order = await transport.wallet.getOrder('order-1');
      expect(order.status, status);
      expect(order.createdAt, null);
      expect(order.fee, null);
      expect(order.toAddress, isEmpty);
      expect(order.targetAmount, null);
    }
    transport.respond({'order': walletTestOrder(biz: 'swap', status: 'done')});
    expect((await transport.wallet.getOrder('order-1')).biz, 'swap');
    expect(
        transport.requests.every((request) => request.method == 'GET'), true);
    await expectLater(
        transport.wallet.getOrder('wrong-order'), throwsFormatException);
  });

  test(
      'conflicting successful withdrawals remain uncertain without automatic retries',
      () async {
    for (final change in <Map<String, dynamic>>[
      {'clientOrderID': 'other'},
      {'amount': '11'},
      {'currency': 'TRX'},
      {'toAddress': 'T-other'},
      {'fee': '2'},
      {'biz': 'swap', 'status': 'done'},
    ]) {
      transport.respond(
          {'order': walletTestOrder()..addAll(change), 'fee': '1.234567'});
      await expectLater(
          withdraw(),
          throwsA(isA<FundApiException>()
              .having((error) => error.isUncertain, 'uncertain', true)
              .having((error) => error.orderID, 'recoverable service ID',
                  'order-1')));
    }
    expect(transport.requests, hasLength(6));
    expect(
        transport.requests.every((request) => request.method == 'POST'), true);
  });

  test('conflicting swap targets, values and malformed success are uncertain',
      () async {
    for (final change in <Map<String, dynamic>>[
      {'targetCurrency': 'TRX'},
      {'targetAmount': '2'},
    ]) {
      transport.respond({
        'order': walletTestOrder(biz: 'swap', status: 'done')
          ..addAll({'targetCurrency': 'BI99', 'targetAmount': '1.23'})
          ..addAll(change),
        'received': '1.23'
      });
      await expectLater(
          swap(),
          throwsA(isA<FundApiException>()
              .having((error) => error.isUncertain, 'uncertain', true)
              .having((error) => error.orderID, 'recoverable service ID',
                  'order-1')));
    }
    transport.respond({
      'order': walletTestOrder(biz: 'swap', status: 'done'),
      'received': 1.23
    });
    await expectLater(swap(), uncertain());
    transport.respond({});
    await expectLater(withdraw(), uncertain());
    expect(transport.requests, hasLength(4));
  });

  test('business errors preserve codes while suppressing backend diagnostics',
      () async {
    for (final code in [
      1001,
      20026,
      20027,
      20028,
      20029,
      20030,
      20031,
      20032,
      20033,
      20034,
      20035,
      20036,
      20037,
      20038,
      401,
      500,
      99999
    ]) {
      transport.body = {
        'errCode': code,
        'errMsg': 'secret-password 123456',
        'errDlt': 'sensitive backend trace'
      };
      await expectLater(
          transport.wallet.fetchDepositAddress(),
          throwsA(isA<FundApiException>()
              .having((error) => error.code, 'code', code)
              .having((error) => error.toString(), 'sanitized error',
                  isNot(contains('123456')))));
      final message = walletFundErrorMessage(
          FundApiException(code, 'secret-password 123456'));
      expect(message, matches(RegExp(r'[\u3400-\u9FFF]')));
      expect(message, isNot(contains('123456')));
    }
    expect(walletFundErrorMessage(const FormatException('Invalid raw payload')),
        matches(RegExp(r'[\u3400-\u9FFF]')));
  });

  test(
      'incomplete write responses keep only a real trimmed service ID for GET recovery',
      () async {
    for (final entry in <(Object?, String?)>[
      ('order-1', 'order-1'),
      (' order-1 ', 'order-1'),
      ('', null),
      (null, null),
      (12, null),
      ('order 1', null),
    ]) {
      transport.respond({'order': walletTestOrder()..['orderID'] = entry.$1});
      await expectLater(
          withdraw(),
          throwsA(isA<FundApiException>()
              .having((error) => error.isUncertain, 'uncertain', true)
              .having((error) => error.orderID, 'service ID', entry.$2)));
    }
    expect(transport.requests, hasLength(6));
  });

  test(
      'wallet messages map payment password errors without changing legacy transport',
      () async {
    expect(walletFundErrorMessage(const FundApiException(20034, 'hidden')),
        contains('设置支付密码'));
    expect(walletFundErrorMessage(const FundApiException(20035, 'hidden')),
        contains('支付密码不正确'));
    expect(walletFundErrorMessage(const FundApiException(20036, 'hidden')),
        contains('15 分钟'));
    expect(walletFundErrorMessage(const FundApiException(401, 'hidden')),
        contains('重新登录'));
    transport.body = {'errCode': 1001, 'errMsg': 'legacy-message'};
    await expectLater(
        transport.fund.fetchBalances(),
        throwsA(isA<FundApiException>().having((error) => error.message,
            'original fund message', 'legacy-message')));
    transport.statusCode = 503;
    transport.failure = DioExceptionType.badResponse;
    await expectLater(
        transport.fund.fetchBalances(),
        throwsA(isA<FundApiException>()
            .having((error) => error.code, 'original HTTP error', -1)));
  });

  test('HTTP 401 and 503 work for both resolved and rejected Dio responses',
      () async {
    for (final failure in [null, DioExceptionType.badResponse]) {
      transport.failure = failure;
      for (final entry in [(401, 401), (503, 500)]) {
        transport.statusCode = entry.$1;
        await expectLater(
            transport.wallet.fetchDepositAddress(),
            throwsA(isA<FundApiException>()
                .having((error) => error.code, 'HTTP code', entry.$2)
                .having((error) => error.isUncertain, 'read outcome', false)));
      }
    }
  });

  test(
      'timeouts leave writes uncertain and never replay an order automatically',
      () async {
    transport.failure = DioExceptionType.receiveTimeout;
    await expectLater(
        transport.wallet.fetchDeposits(),
        throwsA(isA<FundApiException>()
            .having((error) => error.isUncertain, 'read', false)));
    await expectLater(withdraw(), uncertain());
    expect(transport.requests, hasLength(2));
    expect(transport.requests.last.data['clientOrderID'], 'client-1');
  });

  test('missing Chat login is rejected before any wallet request', () async {
    transport.token = null;
    await expectLater(
        transport.wallet.fetchDeposits(),
        throwsA(isA<FundApiException>()
            .having((error) => error.code, 'login', -2)));
    expect(transport.requests, isEmpty);
  });
}
