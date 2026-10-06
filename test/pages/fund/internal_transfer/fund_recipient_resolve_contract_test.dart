import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/internal_transfer/internal_transfer.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim_common/openim_common.dart';

class _Contract {
  _Contract() {
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(
        requestOptions: request,
        statusCode: status,
        data: {'errCode': code, 'data': data, 'errMsg': 'server diagnostics'},
      ));
    }));
  }

  final client = Dio();
  final requests = <RequestOptions>[];
  String owner = 'sender',
      token = 'chat-token',
      server = 'https://chat.example';
  int code = 0, status = 200;
  Map<String, dynamic> data = {
    'user': {
      'userID': 'im_receiver',
      'account': '@abcdefgh12',
      'email': '',
      'nickname': '收款人',
      'faceURL': 'https://images.example/face.png',
      'gender': 0,
      'level': 0,
    }
  };

  FundTransferRecipientSource source({
    FundRecipientResolver? resolver,
    Future<List<UserFullInfo>?> Function(String)? uidLoader,
  }) =>
      FundTransferRecipientSource(
        api: FundApi(
          client: client,
          baseUrl: server,
          tokenProvider: () => token,
        ),
        resolver: resolver,
        uidLoader: uidLoader,
        owner: () => owner,
        tokenProvider: () => token,
        serverProvider: () => server,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('email sends exact-case input to the dedicated authenticated resolver',
      () async {
    final contract = _Contract();
    final source = contract.source();
    final recipient = await source.resolve(
        FundTransferAccountType.email, ' Alice@Example.COM ');
    final request = contract.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.toString(),
        'https://chat.example/chat/fund/recipients/resolve');
    expect(request.headers['token'], 'chat-token');
    expect(request.headers['operationID'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(request.contentType, Headers.jsonContentType);
    expect(request.queryParameters, isEmpty);
    expect(request.data, {
      'recipientType': 'email',
      'recipient': 'Alice@Example.COM',
    });
    expect(recipient.userID, 'im_receiver');
    expect(recipient.account, '@abcdefgh12');
    expect(recipient.nickname, '收款人');
    expect(recipient.faceURL, 'https://images.example/face.png');
    expect(recipient.recipientType, 'email');
    expect(recipient.recipient, 'Alice@Example.COM');
    expect(recipient.areaCode, isNull);
    // The resolver's public response deliberately omits the bound email.
    expect((contract.data['user'] as Map)['email'], '');
  });

  for (final account in ['abcdefgh12', '@abcdefgh12', ' @abcdefgh12 ']) {
    test('public account $account uses canonical account descriptor', () async {
      final contract = _Contract();
      final recipient = await contract
          .source()
          .resolve(FundTransferAccountType.account, account);
      expect(contract.requests.single.data, {
        'recipientType': 'account',
        'recipient': '@abcdefgh12',
      });
      expect(recipient.recipientType, 'account');
      expect(recipient.recipient, '@abcdefgh12');
      expect(recipient.areaCode, isNull);
    });
  }

  for (final phone in [
    (input: '18800000000', area: null, number: '18800000000', code: '+86'),
    (input: '(188) 0000-0000', area: '86', number: '18800000000', code: '+86'),
    (input: '+86 18800000000', area: '+86', number: '18800000000', code: '+86'),
    (input: '+886 912345678', area: '+886', number: '912345678', code: '+886'),
    (input: '02079460000', area: '+44', number: '02079460000', code: '+44'),
  ]) {
    test('phone sends national number and independent region $phone', () async {
      final contract = _Contract();
      final recipient = await contract.source().resolve(
          FundTransferAccountType.phone, phone.input,
          areaCode: phone.area);
      expect(contract.requests.single.data, {
        'recipientType': 'phone',
        'recipient': phone.number,
        'areaCode': phone.code,
      });
      expect(recipient.recipient, phone.number);
      expect(recipient.areaCode, phone.code);
      expect(recipient.userID, 'im_receiver');
      // No private phone fields are needed after the server resolved the user.
      expect(
          (contract.data['user'] as Map).containsKey('phoneNumber'), isFalse);
    });
  }

  for (final entry in [
    (type: FundTransferAccountType.email, input: 'invalid', area: null),
    (type: FundTransferAccountType.account, input: 'im_receiver', area: null),
    (type: FundTransferAccountType.phone, input: '123', area: '+86'),
    (type: FundTransferAccountType.phone, input: '18800000000', area: ''),
    (type: FundTransferAccountType.phone, input: '+886912345678', area: '+86'),
  ]) {
    test('invalid descriptor fails before the resolver $entry', () async {
      final contract = _Contract();
      await expectLater(
          contract
              .source()
              .resolve(entry.type, entry.input, areaCode: entry.area),
          throwsA(isA<FormatException>()));
      expect(contract.requests, isEmpty);
    });
  }

  test('each read gets a fresh operation ID and never generates an order',
      () async {
    final contract = _Contract();
    final source = contract.source();
    await source.resolve(FundTransferAccountType.email, 'alice@example.com');
    await source.resolve(FundTransferAccountType.email, 'alice@example.com');
    expect(contract.requests.map((r) => r.headers['operationID']).toSet(),
        hasLength(2));
    expect(
        contract.requests.every((r) =>
            !(r.data as Map).containsKey('clientOrderID') &&
            !(r.data as Map).containsKey('payPassword') &&
            !(r.data as Map).containsKey('userID')),
        isTrue);
  });

  for (final value in [
    null,
    [],
    {'nickname': '收款人'},
    {'userID': 12},
    {'userID': ''},
    {'userID': 'receiver', 'nickname': 12},
  ]) {
    test('incomplete public profile cannot authorize a recipient $value',
        () async {
      final contract = _Contract()..data = {'user': value};
      await expectLater(
          contract
              .source()
              .resolve(FundTransferAccountType.email, 'alice@example.com'),
          throwsA(isA<FormatException>()));
    });
  }

  for (final user in [
    {'userID': 'sender'},
    {'userID': '99Message'},
    {'userID': '99Pay'},
    {'userID': 'assistant'},
    {'userID': 'service', 'ex': '{"accountType":"official"}'},
  ]) {
    test('resolved self and official accounts remain prohibited $user',
        () async {
      final contract = _Contract()..data = {'user': user};
      await expectLater(
          contract
              .source()
              .resolve(FundTransferAccountType.email, 'service@example.com'),
          throwsA(isA<FormatException>()));
    });
  }

  for (final code in [1001, 20038, 500]) {
    test('business failure $code remains a failure with its diagnostic code',
        () async {
      final contract = _Contract()..code = code;
      await expectLater(
          contract
              .source()
              .resolve(FundTransferAccountType.email, 'alice@example.com'),
          throwsA(isA<FundApiException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.isUncertain, 'read certainty', isFalse)
              .having((e) => e.message, 'message',
                  isNot(contains('diagnostics')))));
    });
  }

  for (final action in ['owner', 'token', 'server', 'cancel', 'close']) {
    test('late resolver results cannot escape changed scope $action', () async {
      final gate = Completer<UserFullInfo?>();
      final contract = _Contract();
      final source = contract.source(
          resolver: ({required recipientType, required recipient, areaCode}) =>
              gate.future);
      final pending =
          source.resolve(FundTransferAccountType.email, 'alice@example.com');
      final rejected = expectLater(pending, throwsA(isA<StateError>()));
      switch (action) {
        case 'owner':
          contract.owner = 'other';
        case 'token':
          contract.token = 'other-token';
        case 'server':
          contract.server = 'https://other.example';
        case 'cancel':
          source.cancel();
        case 'close':
          source.close();
      }
      gate.complete(UserFullInfo(userID: 'receiver'));
      await rejected;
    });
  }

  test('new resolver query invalidates older in-flight query', () async {
    final gates = [Completer<UserFullInfo?>(), Completer<UserFullInfo?>()];
    var calls = 0;
    final source = _Contract().source(
        resolver: ({required recipientType, required recipient, areaCode}) =>
            gates[calls++].future);
    final first =
        source.resolve(FundTransferAccountType.email, 'first@example.com');
    final rejected = expectLater(first, throwsA(isA<StateError>()));
    final second =
        source.resolve(FundTransferAccountType.email, 'second@example.com');
    gates[0].complete(UserFullInfo(userID: 'first'));
    gates[1].complete(UserFullInfo(userID: 'second'));
    await rejected;
    expect((await second).userID, 'second');
  });

  test('UID preserves direct exact IM lookup without an invented resolve type',
      () async {
    final contract = _Contract();
    final loads = <String>[];
    final source = contract.source(uidLoader: (id) async {
      loads.add(id);
      return [UserFullInfo(userID: id, account: '@abcdefgh12')];
    });
    final recipient =
        await source.resolve(FundTransferAccountType.uid, 'im_receiver');
    expect(loads, ['im_receiver']);
    expect(contract.requests, isEmpty);
    expect(recipient.recipientType, isNull);
    expect(recipient.recipient, isNull);
    expect(recipient.areaCode, isNull);
  });
}
