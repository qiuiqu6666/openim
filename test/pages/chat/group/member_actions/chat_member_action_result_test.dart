import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_result.dart';

void main() {
  void check(Object? response) =>
      ensureChatMemberActionSucceeded(response, targetUserID: 'target');

  test('current SDK empty mute and kick callbacks are successful', () {
    for (final response in [
      '""',
      '  ""  ',
      null,
      '',
      '  ',
      'null',
      '{}',
      '[]',
      {},
      [],
    ]) {
      expect(() => check(response), returnsNormally);
    }
  });

  test('old per-member results work as raw JSON and decoded channel values',
      () {
    for (final response in [
      '[{"userID":"target","result":0}]',
      {'userID': 'target', 'result': 0},
      [
        {'userID': 'target', 'result': '0'}
      ],
      '{"errCode":0,"errMsg":"","data":[{"userID":"target","result":0}]}',
    ]) {
      expect(() => check(response), returnsNormally);
    }
  });

  test('a partial failure is rejected even when another row succeeds', () {
    expect(
      () => check('[{"userID":"other","result":0},'
          '{"userID":"target","result":1002}]'),
      throwsA(isA<ChatMemberActionResultException>()
          .having((e) => e.targetUserID, 'targetUserID', 'target')
          .having((e) => e.code, 'code', 1002)),
    );
    expect(
      () => check([
        {'userID': 'target', 'result': 0},
        {'userID': 'other', 'result': 1002},
      ]),
      throwsA(isA<ChatMemberActionResultException>()),
    );
  });

  test('failure envelope preserves server code and message', () {
    expect(
      () => check('{"errCode":1002,"errMsg":" Permission changed "}'),
      throwsA(isA<ChatMemberActionResultException>()
          .having((e) => e.code, 'code', 1002)
          .having((e) => e.toString(), 'message', 'Permission changed')),
    );
    expect(
      () => check('{"errCode":0,"data":[{"userID":"target","result":1002}]}'),
      throwsA(isA<ChatMemberActionResultException>()),
    );
  });

  test('malformed or unknown callback data cannot report false success', () {
    for (final response in [
      'not JSON',
      '"not JSON"',
      'success',
      '"success"',
      1,
      '0',
      true,
      'true',
      {'unexpected': 0},
      {'result': null},
      {'result': 'invalid'},
      {'result': 0.5},
      [null],
      [{}],
    ]) {
      expect(() => check(response),
          throwsA(isA<ChatMemberActionResultException>()));
    }
  });
}
