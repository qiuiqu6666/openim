import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/verification_code_result.dart';
import 'package:openim/pages/mine/settings/widgets/verification_code_flow.dart';

void main() {
  test('backend flags are strict and map to SDK flags', () {
    for (final flags in [
      [false, false],
      [true, false],
      [true, true]
    ]) {
      final result = VerificationCodeResult.fromJson({
        'captchaVerifyResult': flags[0],
        'bizResult': flags[1],
        'retryAfter': 60
      });
      expect(result.sent, flags[0] && flags[1]);
      expect(
          result.sdkResult, {'captchaResult': flags[0], 'bizResult': flags[1]});
    }
    for (final data in [
      {},
      {'captchaVerifyResult': false, 'bizResult': true},
      {'captchaVerifyResult': 'true', 'bizResult': true},
      {'captchaVerifyResult': true, 'bizResult': true, 'retryAfter': 0}
    ]) {
      expect(
          () => VerificationCodeResult.fromJson(data), throwsFormatException);
    }
  });
  testWidgets('registered phone rejection does not start cooldown',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final flow = VerificationCodeFlow(verify: (c, request) => request('proof'));
    addTearDown(flow.dispose);
    await expectLater(
        flow.send(context, (_) async {
          throw (20003, 'PhoneAlreadyRegister');
        }),
        throwsA((20003, 'PhoneAlreadyRegister')));
    expect(flow.remaining, 0);
    expect(flow.canSend, true);
  });
  testWidgets('only actual SMS success starts backend cooldown',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    var now = DateTime(2026);
    var calls = 0;
    final flow = VerificationCodeFlow(
        now: () => now, verify: (c, request) => request(' RAW {proof} '));
    addTearDown(flow.dispose);
    for (final captcha in [false, true]) {
      expect(
          await flow.send(context, (param) async {
            expect(param, ' RAW {proof} ');
            calls++;
            return VerificationCodeResult(
                captchaVerified: captcha, sent: false);
          }),
          false);
      expect(flow.canSend, true);
      expect(flow.remaining, 0);
    }
    await expectLater(
        flow.send(context, (_) async => throw StateError('offline')),
        throwsStateError);
    expect(flow.canSend, true);
    expect(
        await flow.send(context, (param) async {
          calls++;
          return const VerificationCodeResult(
              captchaVerified: true, sent: true, retryAfter: 75);
        }),
        true);
    expect(flow.remaining, 75);
    expect(
        await flow.send(
            context, (_) async => throw StateError('must not send')),
        false);
    expect(calls, 3);
    now = now.add(const Duration(seconds: 75));
    await tester.pump(const Duration(seconds: 1));
    expect(flow.canSend, true);
  });
  testWidgets('cancel and duplicate clicks never issue a request',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final verification = Completer<VerificationCodeResult?>();
    final flow =
        VerificationCodeFlow(verify: (c, request) => verification.future);
    final pending =
        flow.send(context, (_) async => throw StateError('must not send'));
    expect(await flow.send(context, (_) async => throw StateError('duplicate')),
        false);
    verification.complete(null);
    expect(await pending, false);
    expect(flow.canSend, true);
    flow.dispose();
  });
  testWidgets('disposed page blocks a delayed proof', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final proof = Completer<void>();
    final flow = VerificationCodeFlow(verify: (c, request) async {
      await proof.future;
      return request('proof');
    });
    final pending =
        flow.send(context, (_) async => throw StateError('must not send'));
    final assertion = expectLater(pending, throwsStateError);
    flow.dispose();
    proof.complete();
    await assertion;
  });
}
