import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/revocation_fixture.dart';

void main() {
  test('crossing two minutes during confirmation explains blocked request',
      () async {
    final answer = Completer<bool>();
    final f = RevocationFixture(confirm: () => answer.future);
    final task = f.controller
        .revokeMessage(f.message(sender: f.account, ageSeconds: 119));
    f.clock += 1000;
    answer.complete(true);
    await task;
    expect(f.feedback, ['消息已超过两分钟，无法撤回']);
    expect(f.requests, isEmpty);
    expect(f.removed, isEmpty);
    expect(f.events.map((e) => e['stage']),
        ['click', 'confirmation', 'confirmation', 'stopped']);
    expect(f.events.last['outcome'], 'time_limit_exceeded');
  });

  test('expired click explains reason without prompting or dispatch', () async {
    var prompted = false;
    final f = RevocationFixture(confirm: () async {
      prompted = true;
      return true;
    });
    await f.controller
        .revokeMessage(f.message(sender: f.account, ageSeconds: 120));
    expect(prompted, isFalse);
    expect(f.feedback.single, contains('两分钟'));
    expect(f.requests, isEmpty);
  });

  test('message invalidated during confirmation explains cancellation',
      () async {
    final answer = Completer<bool>();
    final f = RevocationFixture(confirm: () => answer.future);
    final task = f.controller.revokeMessage(f.message());
    f.messageCurrent = false;
    answer.complete(true);
    await task;
    expect(f.requests, isEmpty);
    expect(f.feedback.single, contains('状态已变化'));
  });

  test('cancel is logged without a failure toast or SDK invocation', () async {
    final f = RevocationFixture(confirm: () async => false);
    await f.controller.revokeMessage(f.message());
    expect(f.events.last['outcome'], 'cancelled');
    expect(f.feedback, isEmpty);
    expect(f.requests, isEmpty);
  });

  test('SDK results correlate without logging raw errors and allow retry',
      () async {
    final f = RevocationFixture(confirm: () async => true);
    f.onRevoke = () async => throw PlatformException(
        code: '10002', message: 'PRIVATE_MESSAGE token=SECRET');
    await f.controller.revokeMessage(f.message());
    expect(f.feedback, hasLength(1));
    expect(f.removed, isEmpty);
    expect(f.events.map((e) => e['operationID']).toSet(), hasLength(1));
    expect(f.events.where((e) => e['stage'] == 'sdk_call').single['outcome'],
        'started');
    expect(f.events.last['stage'], 'request_result');
    expect(f.events.last['outcome'], 'sdk_failed');
    expect(f.events.last['sdkCode'], '10002');
    expect(f.events.toString(), isNot(contains('SECRET')));
    expect(f.events.toString(), isNot(contains('PRIVATE_MESSAGE')));
    expect(f.events.last['clientMsgID'], 'message');
    f.onRevoke = null;
    await f.controller.revokeMessage(f.message());
    expect(f.events.last['outcome'], 'sdk_success');
    expect(f.removed, ['message']);
    expect(f.events.map((e) => e['operationID']).toSet(), hasLength(2));
  });

  test('confirmation error is reported and releases pending operation',
      () async {
    var fail = true;
    final f = RevocationFixture(confirm: () async {
      if (fail) throw StateError('dialog failed');
      return true;
    });
    await f.controller.revokeMessage(f.message());
    expect(f.feedback, hasLength(1));
    expect(f.events.last['stage'], 'confirmation');
    expect(f.events.last['outcome'], 'failed');
    expect(f.requests, isEmpty);
    fail = false;
    await f.controller.revokeMessage(f.message());
    expect(f.requests, hasLength(1));
  });

  test('late SDK failure is logged but never shown to another account',
      () async {
    final f = RevocationFixture();
    final result = Completer<void>();
    f.onRevoke = () => result.future;
    final task = f.controller.revokeMessage(f.message());
    await Future<void>.delayed(Duration.zero);
    f.account = 'new-account';
    result.completeError(PlatformException(code: '10002'));
    await task;
    expect(f.feedback, isEmpty);
    expect(f.events.any((e) => e['outcome'] == 'sdk_failed'), isTrue);
    expect(f.events.last['outcome'], 'session_changed');
    expect(f.events.last['accountID'], 'admin');
  });
}
