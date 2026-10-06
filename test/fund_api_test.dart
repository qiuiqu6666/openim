import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/fund_api.dart';

Map<String, dynamic> _fundFixture(String name) =>
    jsonDecode(File('test/fixtures/fund/$name').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _order({
  String id = 'order-1',
  String biz = 'transfer',
  String scene = 'single',
  String currency = 'USDT',
  String amount = '12.5',
  String status = 'done',
  String? remark,
}) =>
    {
      'orderID': id,
      'clientOrderID': 'client-1',
      'biz': biz,
      'scene': scene,
      'currency': currency,
      'amount': amount,
      'status': status,
      'senderID': 'me',
      'recvID': scene == 'single' ? 'friend' : '',
      'groupID': scene == 'group' ? 'group-1' : '',
      if (remark != null) 'remark': remark,
    };

void main() {
  group('exact decimal accounting', () {
    test('six- and two-decimal currencies retain their exact smallest units',
        () {
      final usdt = FundAmount.parse('0.000001', FundCurrency.usdt);
      final trx = FundAmount.parse('00012.500000', FundCurrency.trx);
      final bi99 = FundAmount.parse('0.29', FundCurrency.bi99);
      expect(usdt.units, BigInt.one);
      expect(trx.decimal, '12.5');
      expect(bi99.multipliedBy(3).decimal, '0.87');
      expect(FundAmount.parse('9223372036854.775807', FundCurrency.usdt).units,
          BigInt.parse('9223372036854775807'));
      expect(FundCurrency.bi99.displayName, '99BI');
    });

    test('rejects precision loss, signs, exponents and locale separators', () {
      for (final value in [
        '1.001',
        '-1',
        '+1',
        '1e3',
        '1,5',
        '.',
        '1.',
        'NaN'
      ]) {
        expect(() => FundAmount.parse(value, FundCurrency.bi99),
            throwsFormatException);
      }
      expect(() => FundAmount.parse('0.0000001', FundCurrency.usdt),
          throwsFormatException);
      expect(
          () => FundAmount.parse('1', FundCurrency.trx)
              .compareTo(FundAmount.parse('1', FundCurrency.usdt)),
          throwsArgumentError);
    });

    test('display cents do not round six-decimal or large wire amounts', () {
      for (final value in ['10', '2.5', '0.000001', '9223372036854.775807']) {
        final amount = FundAmount.parse(value, FundCurrency.usdt);
        expect(
            FundAmount.parse(amount.displayDecimal, amount.currency), amount);
        expect(amount.decimal, value);
      }
      expect(FundAmount.parse('10', FundCurrency.usdt).displayDecimal, '10.00');
      expect(FundAmount.parse('2.5', FundCurrency.usdt).displayDecimal, '2.50');
    });

    test('client IDs use random UUID v4 rather than a millisecond timestamp',
        () {
      final first = FundApi.createClientOrderID();
      final second = FundApi.createClientOrderID();
      expect(
          first,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(second, isNot(first));
    });
  });

  group('remark contract', () {
    test(
        'trims before counting Unicode code points and leaves defaults to server',
        () {
      final twelveEmoji = List.filled(12, '😀').join();
      expect(twelveEmoji.length, 24);
      expect(FundRemark.normalize(' \t$twelveEmoji\n '), twelveEmoji);
      expect(FundRemark.normalize('  中，文! \n'), '中，文!');
      expect(FundRemark.normalize(' \t\n '), '');
      expect(FundRemark.maxCodePoints, 12);
      expect(FundRemark.defaultPacket, '恭喜发财，大吉大利');
    });

    test('rejects more than twelve code points including combining marks', () {
      for (final remark in [
        List.filled(13, '😀').join(),
        List.filled(7, 'e\u0301').join(),
        '123456789012!',
      ]) {
        expect(() => FundRemark.normalize(remark), throwsFormatException);
      }
      final sixAccentedLetters = List.filled(6, 'e\u0301').join();
      expect(FundRemark.normalize(sixAccentedLetters), sixAccentedLetters);
    });

    test(
        'order metadata keeps the server value and supports legacy missing remark',
        () {
      expect(FundOrder.fromJson(_order()).remark, '');
      expect(FundOrder.fromJson(_order(remark: '')).remark, '');
      expect(FundOrder.fromJson(_order(remark: '  原单备注  ')).remark, '  原单备注  ');
      for (final invalid in [null, 1, true, <String>[], <String, String>{}]) {
        expect(() => FundOrder.fromJson(_order()..['remark'] = invalid),
            throwsFormatException);
      }
    });
  });

  group('fund request contract', () {
    late Dio client;
    late FundApi api;
    late List<RequestOptions> requests;
    late Map<String, dynamic> response;

    setUp(() {
      client = Dio();
      requests = [];
      response = {
        'errCode': 0,
        'data': {'order': _order()}
      };
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: response,
        ));
      }));
      api = FundApi(
        client: client,
        baseUrl: 'https://chat.example.test/',
        tokenProvider: () => 'chat-token',
      );
    });

    tearDown(() => client.close(force: true));

    test('transfer sends a normalized twelve-code-point emoji remark',
        () async {
      final remark = List.filled(12, '😀').join();
      response = {
        'errCode': 0,
        'data': {'order': _order(remark: remark)}
      };
      final order = await api.sendTransfer(
        clientOrderID: 'client-1',
        scene: FundScene.single,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'friend',
        payPassword: '123456',
        remark: ' \t$remark\n ',
      );
      expect(requests.single.data['remark'], remark);
      expect(order.remark, remark);
    });

    test('server first-write remark is authoritative on idempotent retry',
        () async {
      response = {
        'errCode': 0,
        'data': {'order': _order(remark: '首次备注')}
      };
      for (final remark in ['首次备注', '后续备注']) {
        final order = await api.sendTransfer(
          clientOrderID: 'client-1',
          scene: FundScene.single,
          amount: FundAmount.parse('12.5', FundCurrency.usdt),
          recvID: 'friend',
          payPassword: '123456',
          remark: remark,
        );
        expect(order.orderID, 'order-1');
        expect(order.remark, '首次备注');
      }
      expect(requests.map((request) => request.data['clientOrderID']),
          ['client-1', 'client-1']);
      expect(
          requests.map((request) => request.data['remark']), ['首次备注', '后续备注']);
    });

    test(
        'packet sends normalized blessing and accepts the authoritative server value',
        () async {
      response = {
        'errCode': 0,
        'data': {'order': _order(biz: 'packet_normal', remark: '生日快乐🎂')}
      };
      final order = await api.sendPacket(
        clientOrderID: 'client-1',
        scene: FundScene.single,
        biz: FundPacketBiz.normal,
        currency: FundCurrency.usdt,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'friend',
        payPassword: '123456',
        remark: ' 生日快乐🎂 ',
      );
      expect(requests.single.data['remark'], '生日快乐🎂');
      expect(order.remark, '生日快乐🎂');
    });

    test(
        'explicit blank sends empty remark while the server chooses packet default',
        () async {
      response = {
        'errCode': 0,
        'data': {
          'order':
              _order(biz: 'packet_normal', remark: FundRemark.defaultPacket)
        }
      };
      final order = await api.sendPacket(
        clientOrderID: 'client-1',
        scene: FundScene.single,
        biz: FundPacketBiz.normal,
        currency: FundCurrency.usdt,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'friend',
        payPassword: '123456',
        remark: ' \t ',
      );
      expect(requests.single.data['remark'], '');
      expect(order.remark, FundRemark.defaultPacket);
      response = {
        'errCode': 0,
        'data': {'order': _order(remark: '')..['clientOrderID'] = 'client-2'}
      };
      await api.sendTransfer(
        clientOrderID: 'client-2',
        scene: FundScene.single,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'friend',
        payPassword: '123456',
        remark: '',
      );
      expect(requests.last.data.containsKey('remark'), true);
      expect(requests.last.data['remark'], '');
    });

    test('oversized packet or transfer remarks are rejected before transport',
        () async {
      final remark = List.filled(13, '😀').join();
      await expectLater(
          api.sendTransfer(
            clientOrderID: 'client-1',
            scene: FundScene.single,
            amount: FundAmount.parse('12.5', FundCurrency.usdt),
            recvID: 'friend',
            payPassword: '123456',
            remark: remark,
          ),
          throwsFormatException);
      await expectLater(
          api.sendPacket(
            clientOrderID: 'client-1',
            scene: FundScene.single,
            biz: FundPacketBiz.normal,
            currency: FundCurrency.usdt,
            amount: FundAmount.parse('12.5', FundCurrency.usdt),
            recvID: 'friend',
            payPassword: '123456',
            remark: remark,
          ),
          throwsFormatException);
      expect(requests, isEmpty);
    });

    test(
        'server parameter errors keep their code and have a useful remark hint',
        () async {
      response = {'errCode': 1001, 'errMsg': 'ArgsError'};
      await expectLater(
          api.sendTransfer(
            clientOrderID: 'client-1',
            scene: FundScene.single,
            amount: FundAmount.parse('12.5', FundCurrency.usdt),
            recvID: 'friend',
            payPassword: '123456',
            remark: '备注',
          ),
          throwsA(isA<FundApiException>()
              .having((error) => error.code, 'code', 1001)
              .having((error) => error.isUncertain, 'uncertain', false)));
      expect(
          fundErrorMessage(const FundApiException(1001, 'ArgsError'),
              chinese: true),
          contains('备注'));
      expect(
          fundErrorMessage(const FundApiException(1001, 'ArgsError'),
              chinese: false),
          contains('remark'));
    });

    test('transfer uses Chat token and keeps the same idempotency ID on retry',
        () async {
      for (var attempt = 0; attempt < 2; attempt++) {
        final order = await api.sendTransfer(
          clientOrderID: 'client-1',
          scene: FundScene.single,
          amount: FundAmount.parse('12.500000', FundCurrency.usdt),
          recvID: 'friend',
          payPassword: '123456',
        );
        expect(order.orderID, 'order-1');
      }
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.path, 'https://chat.example.test/chat/fund/transfers');
        expect(request.method, 'POST');
        expect(request.headers['token'], 'chat-token');
        expect(request.contentType, Headers.jsonContentType);
        expect(request.data, {
          'clientOrderID': 'client-1',
          'scene': 'single',
          'currency': 'USDT',
          'amount': '12.5',
          'recvID': 'friend',
          'payPassword': '123456',
        });
      }
      expect(requests[0].headers['operationID'],
          isNot(requests[1].headers['operationID']));
    });

    test('group transfer carries only a real selected member and group',
        () async {
      response = {
        'errCode': 0,
        'data': _order(
            biz: 'group_transfer',
            scene: 'group',
            currency: 'BI99',
            amount: '1.23')
          ..['recvID'] = 'member',
      };
      final order = await api.sendTransfer(
        clientOrderID: 'client-1',
        scene: FundScene.group,
        amount: FundAmount.parse('1.23', FundCurrency.bi99),
        recvID: 'member',
        groupID: 'group-1',
        payPassword: '123456',
      );
      expect(order.isTransfer, true);
      expect(requests.single.data['recvID'], 'member');
      expect(requests.single.data['groupID'], 'group-1');
      expect(requests.single.data['currency'], 'BI99');
      expect(requests.single.data.containsKey('userID'), false);
    });

    test('normal group packet sends exact share price and share count',
        () async {
      response = {
        'errCode': 0,
        'data': _order(
            biz: 'packet_normal',
            scene: 'group',
            currency: 'BI99',
            amount: '0.87',
            status: 'open')
          ..['shareAmount'] = '0.29'
          ..['shareCount'] = 3,
      };
      final order = await api.sendPacket(
        clientOrderID: 'client-1',
        scene: FundScene.group,
        biz: FundPacketBiz.normal,
        currency: FundCurrency.bi99,
        shareAmount: FundAmount.parse('0.29', FundCurrency.bi99),
        shareCount: 3,
        groupID: 'group-1',
        payPassword: '123456',
      );
      expect(order.requiresClaim, true);
      expect(requests.single.data, {
        'clientOrderID': 'client-1',
        'scene': 'group',
        'biz': 'packet_normal',
        'currency': 'BI99',
        'shareAmount': '0.29',
        'shareCount': 3,
        'groupID': 'group-1',
        'payPassword': '123456',
      });
    });

    test('lucky packet sends a total; one smallest unit per share is required',
        () async {
      response = {
        'errCode': 0,
        'data': _order(
            biz: 'packet_lucky',
            scene: 'group',
            amount: '0.000003',
            status: 'open')
          ..['shareCount'] = 3,
      };
      await api.sendPacket(
        clientOrderID: 'client-1',
        scene: FundScene.group,
        biz: FundPacketBiz.lucky,
        currency: FundCurrency.usdt,
        amount: FundAmount.parse('0.000003', FundCurrency.usdt),
        shareCount: 3,
        groupID: 'group-1',
        payPassword: '123456',
      );
      expect(requests.single.data['amount'], '0.000003');
      expect(requests.single.data.containsKey('shareAmount'), false);
      await expectLater(
        api.sendPacket(
          clientOrderID: 'client-2',
          scene: FundScene.group,
          biz: FundPacketBiz.lucky,
          currency: FundCurrency.usdt,
          amount: FundAmount.parse('0.000002', FundCurrency.usdt),
          shareCount: 3,
          groupID: 'group-1',
          payPassword: '123456',
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    });

    test('exclusive packet is direct and does not create claim shares',
        () async {
      response = {
        'errCode': 0,
        'data': _order(biz: 'packet_exclusive', scene: 'group'),
      };
      final order = await api.sendPacket(
        clientOrderID: 'client-1',
        scene: FundScene.group,
        biz: FundPacketBiz.exclusive,
        currency: FundCurrency.usdt,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'member',
        groupID: 'group-1',
        payPassword: '123456',
      );
      expect(order.requiresClaim, false);
      expect(requests.single.data['recvID'], 'member');
      expect(requests.single.data.containsKey('shareCount'), false);
    });

    test('balances use GET and enforce all three server balances', () async {
      response = {
        'errCode': 0,
        'data': {
          'balances': FundCurrency.values
              .map((currency) => {
                    'currency': currency.code,
                    'available': '0',
                    'frozen': currency == FundCurrency.usdt ? '0.000001' : '0',
                  })
              .toList(),
        },
      };
      final balances = await api.fetchBalances();
      expect(balances, hasLength(3));
      expect(balances.first.frozen.units, BigInt.one);
      expect(requests.single.method, 'GET');
      expect(requests.single.data, isNull);
      response['data'] = {'balances': []};
      await expectLater(api.fetchBalances(), throwsFormatException);
    });

    test(
        'order lookup takes separate shares and does not trust a mismatched ID',
        () async {
      response = {
        'errCode': 0,
        'data': {
          'order': _order(biz: 'packet_normal', scene: 'group', status: 'open')
            ..['expireAt'] = '2026-10-03T12:00:00Z',
          'shares': [
            {
              'index': 0,
              'amount': '1.5',
              'claimerID': 'me',
              'claimedAt': 1791000000
            },
            {'index': 1, 'amount': '1.5', 'claimerID': ''},
          ],
        },
      };
      final order = await api.getOrder('order-1');
      expect(order.shares, hasLength(2));
      expect(order.claimedShareFor('me')?.amount.decimal, '1.5');
      expect(order.claimedShareFor('other'), null);
      expect(order.expireAt, DateTime.utc(2026, 10, 3, 12));
      expect(requests.single.method, 'GET');
      await expectLater(api.getOrder('another-order'), throwsFormatException);
    });

    // Sanitized real GET shapes preserve absent sender identity, null shares,
    // decimal-string zero fields, and integer millisecond timestamps.
    for (final fixture in const [
      (
        file: 'packet-order-without-sender.json',
        orderID: 'packet-fixture-1',
        biz: 'packet_normal',
        scene: FundScene.single,
        currency: FundCurrency.bi99,
        groupID: '',
        remark: '测试祝福',
        createdAt: 1791032141597,
      ),
      (
        file: 'group-transfer-order-without-sender.json',
        orderID: 'transfer-fixture-1',
        biz: 'group_transfer',
        scene: FundScene.group,
        currency: FundCurrency.usdt,
        groupID: 'fixture-group',
        remark: '测试备注',
        createdAt: 1791032256531,
      ),
    ]) {
      test('real GET ${fixture.biz} parses without inventing a sender',
          () async {
        response = _fundFixture(fixture.file);
        final data = response['data'] as Map<String, dynamic>;
        final rawOrder = data['order'] as Map<String, dynamic>;
        expect(rawOrder.containsKey('senderID'), isFalse);
        expect(rawOrder.containsKey('sender_id'), isFalse);
        expect(data['shares'], isNull);

        final order = await api.getOrder(fixture.orderID);

        expect(order.orderID, fixture.orderID);
        expect(order.biz, fixture.biz);
        expect(order.scene, fixture.scene);
        expect(order.currency, fixture.currency);
        expect(order.amount, FundAmount.parse('10', fixture.currency));
        expect(order.status, 'done');
        expect(order.recvID, 'fixture-recipient');
        expect(order.groupID, fixture.groupID);
        expect(order.senderID, isEmpty);
        expect(order.clientOrderID, isEmpty);
        expect(order.shareAmount, FundAmount.zero(fixture.currency));
        expect(order.shareCount, 0);
        expect(order.shares, isEmpty);
        expect(order.requiresClaim, isFalse);
        expect(order.expireAt, isNull);
        expect(
            order.createdAt,
            DateTime.fromMillisecondsSinceEpoch(fixture.createdAt,
                isUtc: true));
        expect(order.remark, fixture.remark);
        expect(requests.single.method, 'GET');
        expect(requests.single.path,
            'https://chat.example.test/chat/fund/orders/${fixture.orderID}');
        expect(requests.single.data, isNull);
      });
    }

    test('claim sends no password and keeps business errors identifiable',
        () async {
      response = {
        'errCode': 0,
        'data': {'amount': '0.000001'}
      };
      final result = await api.claimPacket('order-1');
      expect(result.orderID, 'order-1');
      expect(result.amount, '0.000001');
      expect(requests.single.path, endsWith('/packets/order-1/claim'));
      expect(requests.single.method, 'POST');
      expect(requests.single.data, isNull);
      for (final code in [20028, 20029, 20033, 20035, 20036]) {
        response = {'errCode': code, 'errMsg': 'FundError'};
        await expectLater(
            api.claimPacket('order-1'),
            throwsA(isA<FundApiException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.isUncertain, 'uncertain', false)));
      }
      expect(
          fundErrorMessage(
              const FundApiException(20036, 'FundPayPasswordLocked'),
              chinese: true),
          contains('15 分钟'));
    });

    test('timeout or malformed successful writes preserve uncertain outcome',
        () async {
      response = {'errCode': 0, 'data': {}};
      await expectLater(
        api.sendTransfer(
          clientOrderID: 'client-1',
          scene: FundScene.single,
          amount: FundAmount.parse('12.5', FundCurrency.usdt),
          recvID: 'friend',
          payPassword: '123456',
        ),
        throwsA(isA<FundApiException>()
            .having((e) => e.isUncertain, 'uncertain', true)),
      );
      client.interceptors.clear();
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.reject(DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        ));
      }));
      await expectLater(
          api.claimPacket('order-1'),
          throwsA(isA<FundApiException>()
              .having((e) => e.isUncertain, 'uncertain', true)));
    });

    test('an ID-only write confirms the order using GET', () async {
      client.interceptors.clear();
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'errCode': 0,
          'data': request.method == 'POST'
              ? {'orderID': 'order-1'}
              : {'order': _order()},
        }));
      }));
      final order = await api.sendTransfer(
        clientOrderID: 'client-1',
        scene: FundScene.single,
        amount: FundAmount.parse('12.5', FundCurrency.usdt),
        recvID: 'friend',
        payPassword: '123456',
      );
      expect(order.orderID, 'order-1');
      expect(requests.map((request) => request.method), ['POST', 'GET']);
    });

    test('a conflicting idempotent order is never displayed as this payment',
        () async {
      for (final change in <Map<String, dynamic>>[
        {'clientOrderID': 'another-client'},
        {'amount': '12.6'},
        {'currency': 'TRX'},
        {'scene': 'group'},
        {'recvID': 'another-recipient'},
        {'biz': 'packet_normal'},
      ]) {
        response = {
          'errCode': 0,
          'data': {'order': _order()..addAll(change)},
        };
        await expectLater(
          api.sendTransfer(
            clientOrderID: 'client-1',
            scene: FundScene.single,
            amount: FundAmount.parse('12.5', FundCurrency.usdt),
            recvID: 'friend',
            payPassword: '123456',
          ),
          throwsA(isA<FundApiException>()
              .having((e) => e.isUncertain, 'uncertain', true)),
        );
      }
    });

    test(
        'int64 overflow in one amount or a group total is rejected before dispatch',
        () async {
      await expectLater(
        api.sendTransfer(
          clientOrderID: 'client-1',
          scene: FundScene.single,
          amount: FundAmount.parse('9223372036854.775808', FundCurrency.usdt),
          recvID: 'friend',
          payPassword: '123456',
        ),
        throwsFormatException,
      );
      await expectLater(
        api.sendPacket(
          clientOrderID: 'client-1',
          scene: FundScene.group,
          biz: FundPacketBiz.normal,
          currency: FundCurrency.usdt,
          shareAmount:
              FundAmount.parse('4611686018427.387904', FundCurrency.usdt),
          shareCount: 2,
          groupID: 'group-1',
          payPassword: '123456',
        ),
        throwsFormatException,
      );
      expect(requests, isEmpty);
    });

    test('claim cannot report a different order or a rounded numeric amount',
        () async {
      for (final result in [
        {'amount': '1', 'orderID': 'another-order'},
        {'amount': 0.1},
        {'amount': '0'},
        {'amount': '0.0000001'},
      ]) {
        response = {'errCode': 0, 'data': result};
        await expectLater(
            api.claimPacket('order-1'),
            throwsA(isA<FundApiException>()
                .having((e) => e.isUncertain, 'uncertain', true)));
      }
    });

    test('local invalid requests and missing Chat login never reach transport',
        () async {
      await expectLater(
        api.sendTransfer(
          clientOrderID: 'client-1',
          scene: FundScene.group,
          amount: FundAmount.parse('0', FundCurrency.usdt),
          recvID: 'friend',
          payPassword: '123456',
        ),
        throwsFormatException,
      );
      await expectLater(
        api.sendPacket(
          clientOrderID: 'client-1',
          scene: FundScene.single,
          biz: FundPacketBiz.lucky,
          currency: FundCurrency.usdt,
          amount: FundAmount.parse('1', FundCurrency.usdt),
          recvID: 'friend',
          payPassword: '123456',
        ),
        throwsFormatException,
      );
      final signedOut = FundApi(
          client: client,
          baseUrl: 'https://chat.example.test',
          tokenProvider: () => null);
      await expectLater(signedOut.fetchBalances(),
          throwsA(isA<FundApiException>().having((e) => e.code, 'code', -2)));
      expect(requests, isEmpty);
    });
  });
}
