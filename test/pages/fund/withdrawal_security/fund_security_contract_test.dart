import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/withdrawal_security/withdrawal_security.dart';
import 'package:openim/services/fund_api.dart';

Map<String, dynamic> _transfer() => {
      'clientOrderID': 'original-id',
      'scene': 'single',
      'currency': 'USDT',
      'amount': '10.123456',
      'recvID': 'im_receiver',
      'remark': '原备注',
    };

Map<String, dynamic> _check() => {
      'smsRequired': true,
      'reasons': ['new_device', 'amount_threshold'],
      'blockedUntil': 0,
      'phoneMasked': '+86 138****8000',
      'currency': 'USDT',
      'smsThreshold': '5',
      'cooldownHours': 24,
    };

Map<String, dynamic> _challenge() => {
      'challengeID': 'latest-challenge',
      'expiresAt': 1791252300000,
      'retryAfterSeconds': 60,
      'phoneMasked': '+86 138****8000',
    };

class _Api extends FundApi {
  final calls = <({
    String path,
    String method,
    Map<String, dynamic>? data,
    bool mutation
  })>[];
  Map<String, dynamic> check = _check();
  Map<String, dynamic> challenge = _challenge();

  @override
  Future<Map<String, dynamic>> requestData(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool mutation = false,
  }) async {
    calls.add((path: path, method: method, data: data, mutation: mutation));
    return path.endsWith('/check') ? check : challenge;
  }
}

void main() {
  test(
      'check and send freeze the same business fields without PIN or UI fields',
      () async {
    final original = _transfer()
      ..addAll({
        'payPassword': '123456',
        'verifyCode': '654321',
        'verifyChallengeID': 'old',
        'userID': 'forged-payer',
        'deviceID': 'forged-device',
        'toAddress': 'chain-only',
        'uiAmount': '0',
      });
    final request = FundSecurityRequest.transfer(original);
    original['amount'] = '999';
    final api = _Api();
    final security = FundWithdrawalSecurityApi(api);
    await security.check(request);
    await security.send(request);
    expect(api.calls.map((call) => call.path), [
      '/chat/fund/withdrawal-security/check',
      '/chat/fund/withdrawal-security/code',
    ]);
    for (final call in api.calls) {
      expect(call.method, 'POST');
      expect(call.mutation, isFalse);
      expect(call.data, {'transfer': _transfer()});
    }
    expect(() => request.fields['amount'] = '2', throwsUnsupportedError);
    final outbound = request.toJson();
    (outbound['transfer'] as Map)['amount'] = '33';
    expect(request.fields['amount'], '10.123456');
  });

  test('withdrawal whitelist retains exact phone case and area code', () {
    final request = FundSecurityRequest.withdrawal({
      'clientOrderID': 'id',
      'mode': 'internal',
      'currency': 'BI99',
      'amount': '0.01',
      'recipientType': 'phone',
      'recipient': '18800000000',
      'areaCode': '+86',
      'remark': '内部转账',
      'recvID': 'not-a-withdrawal-field',
      'payPassword': '123456',
      'verification': {},
    });
    expect(request.toJson(), {
      'withdrawal': {
        'clientOrderID': 'id',
        'mode': 'internal',
        'currency': 'BI99',
        'amount': '0.01',
        'recipientType': 'phone',
        'recipient': '18800000000',
        'areaCode': '+86',
        'remark': '内部转账',
      }
    });
  });

  test('chain fields are preserved without inventing recipient data', () {
    final body = {
      'clientOrderID': 'id',
      'mode': 'chain',
      'currency': 'TRX',
      'amount': '10',
      'network': 'TRON',
      'toAddress': 'real-user-address'
    };
    expect(FundSecurityRequest.withdrawal(body).toJson(), {'withdrawal': body});
  });

  for (final entry in <String, dynamic>{
    'clientOrderID': '',
    'currency': 'OTHER',
    'amount': '0',
    'numberAmount': 10,
    'precision': '0.1234567',
  }.entries) {
    test('invalid transaction parameter ${entry.key} does not proceed', () {
      final body = _transfer();
      body[entry.key == 'numberAmount' || entry.key == 'precision'
          ? 'amount'
          : entry.key] = entry.value;
      expect(() => FundSecurityRequest.transfer(body), throwsFormatException);
    });
  }

  test('strict check parser rejects missing, wrong typed and negative values',
      () {
    for (final body in [
      <String, dynamic>{},
      {..._check(), 'smsRequired': 'false'},
      {..._check(), 'blockedUntil': -1},
      {..._check(), 'blockedUntil': '0'},
      {
        ..._check(),
        'reasons': [1]
      },
      {..._check(), 'phoneMasked': null},
      {..._check(), 'smsThreshold': '-1'},
      {..._check(), 'currency': 'OTHER'},
      {..._check(), 'cooldownHours': null},
    ]) {
      expect(() => FundSecurityCheck.fromJson(body), throwsFormatException);
    }
    final check = FundSecurityCheck.fromJson(_check());
    expect(check.smsRequired, isTrue);
    expect(() => check.reasons.add('unexpected'), throwsUnsupportedError);
  });

  test('SMS malformed success never authorizes a payment', () {
    for (final body in [
      <String, dynamic>{},
      {..._challenge(), 'challengeID': ''},
      {..._challenge(), 'phoneMasked': ''},
      {..._challenge(), 'expiresAt': 0},
      {..._challenge(), 'expiresAt': '1791252300000'},
      {..._challenge(), 'retryAfterSeconds': -1},
    ]) {
      expect(() => FundSecurityChallenge.fromJson(body), throwsFormatException);
    }
  });

  test('precheck currency must match original amount currency', () async {
    final api = _Api()..check = {..._check(), 'currency': 'TRX'};
    expect(
        FundWithdrawalSecurityApi(api)
            .check(FundSecurityRequest.transfer(_transfer())),
        throwsFormatException);
  });

  test('proof has only submit verification fields; expiry is not sent', () {
    expect(const FundSecurityProof().toJson(), isEmpty);
    expect(
        const FundSecurityProof(
                challengeID: 'new', code: '012345', expiresAt: 1)
            .toJson(),
        {'verifyChallengeID': 'new', 'verifyCode': '012345'});
    expect(const FundSecurityProof(expiresAt: 1).isExpired, isTrue);
    expect(const FundSecurityProof().isExpired, isFalse);
    expect(() => const FundSecurityProof(challengeID: 'id').toJson(),
        throwsFormatException);
    expect(
        () =>
            const FundSecurityProof(challengeID: 'id', code: '12345').toJson(),
        throwsFormatException);
  });

  test('waiting deadline consistently uses UTC+8 independent of host zone', () {
    expect(
        fundSecurityAllowedTime(
            DateTime.utc(2026, 10, 6, 0, 1, 2).millisecondsSinceEpoch),
        '2026-10-06 08:01:02（UTC+8）');
  });

  test('all transaction SMS errors have Chinese actionable text', () {
    for (final code in [20076, 20077, 20078, 20079, 20080, 20038]) {
      final message =
          fundSecurityErrorMessage(FundApiException(code, 'raw backend text'));
      expect(message, isNot(contains('raw backend')));
      expect(message, matches(RegExp('[\u4e00-\u9fff]')));
    }
    expect(
        fundSecurityErrorMessage(const FundApiException(500, 'server broken')),
        contains('500'));
  });
}
