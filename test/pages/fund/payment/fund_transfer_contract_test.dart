import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/payment/fund_transfer_authorization.dart';
import 'package:openim/services/fund_api.dart';

Map<String, dynamic> _order() => {
      'orderID': 'server-order',
      'clientOrderID': 'client-1',
      'biz': 'transfer',
      'scene': 'internal',
      'currency': 'USDT',
      'amount': '12.5',
      'status': 'done',
      'senderID': 'me',
      'recvID': 'im_receiver',
      'remark': '转账',
      'recipientType': 'phone',
      'recipient': '2025550100',
      'recipientAreaCode': '+1',
      'fee': '0',
    };

Map<String, dynamic> _request() => {
      'clientOrderID': 'client-1',
      'scene': 'internal',
      'currency': 'USDT',
      'amount': '12.5',
      'recvID': 'im_receiver',
      'remark': '转账',
      'recipientType': 'phone',
      'recipient': '2025550100',
      'areaCode': '+1',
    };

void main() {
  late Dio client;
  late FundApi api;
  late Map<String, dynamic> response;
  late List<RequestOptions> requests;

  setUp(() {
    client = Dio();
    response = {
      'errCode': 0,
      'data': {'order': _order()}
    };
    requests = [];
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(
          Response(requestOptions: request, statusCode: 200, data: response));
    }));
    api = FundApi(
        client: client,
        baseUrl: 'https://chat.example.test/',
        tokenProvider: () => 'chat-token');
  });
  tearDown(() => client.close(force: true));

  test('internal transfer uses documented payload and parses server metadata',
      () async {
    final order = await api.sendTransfer(
        clientOrderID: 'client-1',
        scene: FundScene.internal,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'im_receiver',
        payPassword: '123456',
        remark: '转账',
        recipientType: 'phone',
        recipient: '2025550100',
        areaCode: '+1',
        verifyChallengeID: 'current-challenge',
        verifyCode: '482917');
    expect(requests.single.uri.path, '/chat/fund/transfers');
    expect(requests.single.method, 'POST');
    expect(requests.single.data, {
      ..._request(),
      'payPassword': '123456',
      'verifyChallengeID': 'current-challenge',
      'verifyCode': '482917',
    });
    expect(requests.single.headers['token'], 'chat-token');
    expect(requests.single.headers['operationID'], isNotEmpty);
    expect(order.scene, FundScene.internal);
    expect(order.recvID, 'im_receiver');
    expect(order.recipientType, 'phone');
    expect(order.recipient, '2025550100');
    expect(order.recipientAreaCode, '+1');
    expect(order.fee, '0');
  });

  test('by-client recovery reads the original order without payment secrets',
      () async {
    final order = await FundTransferAuthorization(api).recover(_request());
    expect(order?.orderID, 'server-order');
    expect(requests.single.uri.path, '/chat/fund/orders/by-client');
    expect(requests.single.method, 'GET');
    expect(requests.single.queryParameters, {'clientOrderID': 'client-1'});
    expect(requests.single.data, isNull);
    expect(requests.single.headers['token'], 'chat-token');
  });

  test(
      'single with a recipient descriptor recovers the normalized internal scene',
      () async {
    final order = await FundTransferAuthorization(api)
        .recover(_request()..['scene'] = 'single');
    expect(order?.scene, FundScene.internal);
    expect(order?.orderID, 'server-order');
    expect(requests, hasLength(1));
  });

  test('legacy receiver-only orders recover without recipient metadata',
      () async {
    final original = _request()
      ..['scene'] = 'single'
      ..remove('recipientType')
      ..remove('recipient')
      ..remove('areaCode');
    response = {
      'errCode': 0,
      'data': {
        'order': _order()
          ..['scene'] = 'single'
          ..remove('recipientType')
          ..remove('recipient')
          ..remove('recipientAreaCode')
      }
    };
    final order = await FundTransferAuthorization(api).recover(original);
    expect(order?.scene, FundScene.single);
    expect(order?.recipientType, isEmpty);
    expect(order?.recipient, isEmpty);
    expect(order?.recipientAreaCode, isEmpty);
    expect(requests, hasLength(1));
  });

  test('phone recovery accepts the documented default +86 area code', () async {
    final original = _request()..remove('areaCode');
    response = {
      'errCode': 0,
      'data': {'order': _order()..['recipientAreaCode'] = '+86'}
    };
    final order = await FundTransferAuthorization(api).recover(original);
    expect(order?.recipientAreaCode, '+86');
    expect(requests, hasLength(1));
  });

  test('phone submission may omit area code and receive its default +86',
      () async {
    response = {
      'errCode': 0,
      'data': {'order': _order()..['recipientAreaCode'] = '+86'}
    };
    final order = await api.sendTransfer(
        clientOrderID: 'client-1',
        scene: FundScene.internal,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'im_receiver',
        payPassword: '123456',
        remark: '转账',
        recipientType: 'phone',
        recipient: '2025550100');
    expect(order.recipientAreaCode, '+86');
    expect((requests.single.data as Map).containsKey('areaCode'), isFalse);
  });

  for (final mismatch in {
    'recipientType': 'email',
    'recipient': 'another-recipient',
    'recipientAreaCode': '+86',
  }.entries) {
    test('recovery rejects a changed ${mismatch.key} descriptor', () async {
      response = {
        'errCode': 0,
        'data': {'order': _order()..[mismatch.key] = mismatch.value}
      };
      await expectLater(
          FundTransferAuthorization(api).recover(_request()),
          throwsA(isA<FundApiException>()
              .having((error) => error.code, 'code', 20062)));
      expect(requests, hasLength(1));
    });

    test('an accepted write with changed ${mismatch.key} stays uncertain',
        () async {
      response = {
        'errCode': 0,
        'data': {'order': _order()..[mismatch.key] = mismatch.value}
      };
      await expectLater(
          api.sendTransfer(
              clientOrderID: 'client-1',
              scene: FundScene.internal,
              amount: FundAmount.parse('12.5', FundCurrency.usdt),
              recvID: 'im_receiver',
              payPassword: '123456',
              remark: '转账',
              recipientType: 'phone',
              recipient: '2025550100',
              areaCode: '+1'),
          throwsA(isA<FundApiException>()
              .having((error) => error.isUncertain, 'isUncertain', true)));
      expect(requests, hasLength(1));
    });
  }

  for (final mismatch in {
    'recvID': 'another-recipient',
    'amount': '13',
    'currency': 'TRX',
    'scene': 'single',
    'remark': 'another remark',
    'groupID': 'another-group',
    'status': 'open',
  }.entries) {
    test('recovery rejects a mismatched ${mismatch.key}', () async {
      response = {
        'errCode': 0,
        'data': {'order': _order()..[mismatch.key] = mismatch.value}
      };
      await expectLater(
          FundTransferAuthorization(api).recover(_request()),
          throwsA(isA<FundApiException>()
              .having((error) => error.code, 'code', 20062)));
      expect(requests, hasLength(1));
    });
  }

  test('only a definite missing order permits a later original-ID submission',
      () async {
    response = {'errCode': 20032, 'errMsg': 'Order not found', 'data': {}};
    expect(await FundTransferAuthorization(api).recover(_request()), isNull);
    response = {'errCode': 20026, 'errMsg': 'Other failure', 'data': {}};
    await expectLater(
        FundTransferAuthorization(api).recover(_request()),
        throwsA(isA<FundApiException>()
            .having((error) => error.code, 'code', 20026)));
  });

  for (final code in [20062, 500, 503]) {
    test('transfer error $code preserves an uncertain original business ID',
        () async {
      response = {'errCode': code, 'errMsg': 'Service error', 'data': {}};
      await expectLater(
          api.sendTransfer(
              clientOrderID: 'client-1',
              scene: FundScene.internal,
              amount: FundAmount.parse('12.5', FundCurrency.usdt),
              recvID: 'im_receiver',
              payPassword: '123456',
              remark: '转账'),
          throwsA(isA<FundApiException>()
              .having((error) => error.code, 'code', code)
              .having((error) => error.isUncertain, 'isUncertain', true)));
      expect(requests, hasLength(1));
      expect(requests.single.data['clientOrderID'], 'client-1');
    });
  }

  test('by-client response cannot acknowledge a different client order ID',
      () async {
    response = {
      'errCode': 0,
      'data': {'order': _order()..['clientOrderID'] = 'another-client'}
    };
    await expectLater(api.getOrderByClient('client-1'), throwsFormatException);
  });
}
