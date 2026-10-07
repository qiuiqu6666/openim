import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_game_type.dart';

void main() {
  test('top-level numeric gameType selects the public group display', () {
    expect(GroupGameType.fromEx('{"gameType":0}'), GroupGameType.ordinary);
    expect(GroupGameType.fromEx('{"gameType":1}'), GroupGameType.sangong);
    expect(GroupGameType.fromEx('{"gameType":2}'), GroupGameType.markSixAgent);
    expect(GroupGameType.fromEx('{"gameType":3}'), GroupGameType.markSix);
    expect(GroupGameType.fromEx('{"gameType":4}'), GroupGameType.sangongAgent);
    expect(GroupGameType.fromEx('{"gameType":1.0}'), GroupGameType.sangong);
    expect(
        GroupGameType.fromEx('{"gameType":2.0}'), GroupGameType.markSixAgent);
    expect(GroupGameType.fromEx('{"gameType":3.0}'), GroupGameType.markSix);
    expect(
        GroupGameType.fromEx('{"gameType":4.0}'), GroupGameType.sangongAgent);
    expect(GroupGameType.fromEx('{"gameType":1e0}'), GroupGameType.sangong);
  });

  test('missing, malformed, non-object and unsupported values are ordinary',
      () {
    for (final ex in <String?>[
      null,
      '',
      'not-json',
      '{"gameType":',
      '{}',
      'null',
      '[]',
      '[{"gameType":1}]',
      '1',
      'true',
      '"sangong"',
      '{"gameType":null}',
      '{"gameType":"1"}',
      '{"gameType":"2"}',
      '{"gameType":"3"}',
      '{"gameType":"4"}',
      '{"gameType":true}',
      '{"gameType":false}',
      '{"gameType":-1}',
      '{"gameType":5}',
      '{"gameType":1.5}',
      '{"gameType":{}}',
      '{"gameType":[]}',
      '{"groupFeatures":{"gameType":1}}',
      '{"GameType":1}',
    ]) {
      expect(GroupGameType.fromEx(ex), GroupGameType.ordinary, reason: ex);
    }
  });

  test('unrelated nested metadata does not override the top-level type', () {
    const ex = ' {"gameType":3,"custom":{"caption":"保留",'
        '"gameType":1},"groupFeatures":{"schemaVersion":1,"revision":7}} ';
    expect(GroupGameType.fromEx(ex), GroupGameType.markSix);
  });
}
