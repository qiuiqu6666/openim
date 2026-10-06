import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/friend_requests/source/friend_application_source.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  test('signed metadata exposes the server supplied adding method only', () {
    const metadata =
        '{"v":1,"op":"private-operation","mac":"private-signature","addSource":"account"}';
    expect(friendApplicationSource(metadata), FriendAddSource.account);
    expect(friendApplicationSourceLabel(metadata, english: false), '通过99号添加');
    expect(friendApplicationSourceLabel(metadata, english: true),
        'Added via 99 ID');
  });

  for (final source in FriendAddSource.values) {
    test('explicit ${source.name} supports both metadata keys', () {
      expect(friendApplicationSource('{"addSource":"${source.name}"}'), source);
      expect(friendApplicationSource('{"source":"${source.name}"}'), source);
      expect(
          friendApplicationSourceLabel('{"addSource":"${source.name}"}',
              english: false),
          isNot('来源未知'));
    });
  }

  for (final extension in <String?>[
    null,
    '',
    'not-json',
    '[]',
    'null',
    '{"v":1,"op":"private-operation","mac":"private-signature"}',
    '{"reqMsg":"通过群聊添加"}',
    '{"addSource":"im_original-id"}',
    '{"addSource":{"source":"account"}}',
    '{"addSource":42,"source":"account"}',
  ]) {
    test('missing or invalid metadata cannot invent a source: $extension', () {
      expect(friendApplicationSource(extension), isNull);
      expect(friendApplicationSourceLabel(extension, english: false), '来源未知');
      expect(friendApplicationSourceLabel(extension, english: true),
          'Source unknown');
    });
  }
}
