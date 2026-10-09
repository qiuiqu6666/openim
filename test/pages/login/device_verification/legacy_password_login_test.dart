import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/apis/auth/legacy_password_login.dart';
import 'package:openim_common/src/apis/auth/legacy_password_envelope.dart';
import 'dart:convert';

void main() {
  const request = <String, dynamic>{
    'account': 'owner',
    'password': 'synthetic-md5',
    'passwordPlaintext': 'synthetic-original-password',
    'deviceID': 'one-device',
    'verifyCode': '123456',
  };

  test('normal and device challenge requests never expose the raw password',
      () async {
    for (final code in [0, 20081, 20001, 20002]) {
      final sent = <Map<String, dynamic>>[];
      final future = LegacyPasswordLogin.submit(
        request: request,
        endpoint: Uri.parse('http://129.226.192.93:10008/account/login'),
        post: (payload) async {
          sent.add(payload);
          if (code != 0) throw (code, 'business failure');
          return 'certificate';
        },
      );
      if (code == 0) {
        expect(await future, 'certificate');
      } else {
        await expectLater(future, throwsA(anything));
      }
      expect(sent, hasLength(1));
      expect(sent.single.containsKey('passwordPlaintext'), isFalse);
      expect(request['passwordPlaintext'], 'synthetic-original-password');
    }
  });

  test('one encrypted HTTP retry preserves owner, device and SMS proof',
      () async {
    final sent = <Map<String, dynamic>>[];
    final result = await LegacyPasswordLogin.submit(
      request: request,
      endpoint: Uri.parse('http://129.226.192.93:10008/account/login'),
      post: (payload) async {
        sent.add(payload);
        if (sent.length == 1) throw (20084, 'legacy proof required');
        return 'certificate';
      },
    );
    expect(result, 'certificate');
    expect(sent, hasLength(2));
    expect(sent.first.containsKey('passwordPlaintext'), isFalse);
    expect(sent.last['passwordPlaintext'],
        startsWith(LegacyPasswordEnvelope.prefix));
    expect(sent.last['passwordPlaintext'], isNot(request['passwordPlaintext']));
    final proof = sent.last['passwordPlaintext'] as String;
    expect(base64Decode(proof.substring(LegacyPasswordEnvelope.prefix.length)),
        hasLength(384));
    expect({...sent.last}..remove('passwordPlaintext'),
        {...request}..remove('passwordPlaintext'));
  });

  test(
      'untrusted hosts, URL credentials and invalid schemes cannot receive proofs',
      () async {
    for (final endpoint in [
      'http://example.invalid/account/login',
      'http://login:secret@129.226.192.93/account/login',
      'http://129.226.192.93.example.invalid/account/login',
      'ftp://129.226.192.93/account/login',
      '/account/login',
    ]) {
      var sent = 0;
      await expectLater(
        LegacyPasswordLogin.submit(
          request: request,
          endpoint: Uri.parse(endpoint),
          post: (_) async {
            sent++;
            throw (20084, 'legacy proof required');
          },
        ),
        throwsFormatException,
      );
      expect(sent, 1);
    }
  });

  test('cancelled attempts and old clients cannot manufacture a raw proof',
      () async {
    for (final cancelled in [false, true]) {
      var sent = 0;
      final input = Map<String, dynamic>.from(request);
      if (!cancelled) input.remove('passwordPlaintext');
      await expectLater(
        LegacyPasswordLogin.submit(
          request: input,
          endpoint: Uri.parse('http://129.226.192.93:10008/account/login'),
          isCurrent: () => !cancelled,
          post: (_) async {
            sent++;
            throw (20084, 'legacy proof required');
          },
        ),
        throwsA(anything),
      );
      expect(sent, 1);
    }
  });

  test('a rejected legacy proof does not loop or fall back to SMS login',
      () async {
    var sent = 0;
    await expectLater(
      LegacyPasswordLogin.submit(
        request: request,
        endpoint: Uri.parse('http://129.226.192.93:10008/account/login'),
        post: (_) async {
          sent++;
          throw (20084, 'legacy proof required');
        },
      ),
      throwsA(anything),
    );
    expect(sent, 2);
  });
}
