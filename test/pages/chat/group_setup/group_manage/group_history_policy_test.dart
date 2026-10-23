import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group_setup/group_manage/history_visibility/group_history_policy.dart';

void main() {
  test('matches server defaults and explicit policies', () {
    for (final ex in [
      null,
      '',
      'legacy',
      '[]',
      '{}',
      '{"enableHistoryForNewMembers":null}'
    ]) {
      expect(GroupHistoryPolicy.read(ex), isTrue);
    }
    expect(GroupHistoryPolicy.read('{"enableHistoryForNewMembers":false}'),
        isFalse);
    expect(GroupHistoryPolicy.read('{"enableHistoryForNewMembers":"true"}'),
        isFalse);
  });
  test('merges only history policy and rejects destructive legacy overwrite',
      () {
    final merged = jsonDecode(GroupHistoryPolicy.merge(
        '{"gameType":3,"groupPersonalization":{"color":123}}', false));
    expect(merged, {
      'gameType': 3,
      'groupPersonalization': {'color': 123},
      'enableHistoryForNewMembers': false
    });
    for (final ex in ['legacy', '[]', 'null']) {
      expect(() => GroupHistoryPolicy.merge(ex, true), throwsFormatException);
    }
  });
}
