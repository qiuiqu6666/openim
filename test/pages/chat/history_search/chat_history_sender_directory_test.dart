import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_directory.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';

ChatHistorySender sender(String id, String name,
        {String? avatar, String? nickname}) =>
    ChatHistorySender(
        userID: id, displayName: name, faceURL: avatar, nickname: nickname);

List<String> ids(ChatHistorySenderDirectory directory) =>
    [for (var i = 0; i < directory.length; i++) directory[i].userID];

void main() {
  test('Chinese, Latin and symbol names retain their source order', () {
    final source = [
      sender('autumn', '秋'),
      sender('number', '123'),
      sender('winter', '冬'),
      sender('alice', 'alice'),
      sender('symbol', '!用户'),
      sender('bob', 'Bob'),
    ];
    final directory = ChatHistorySenderDirectory()..addPage(source);
    expect(ids(directory), source.map((member) => member.userID));
  });

  test('duplicates and empty IDs are removed without replacing callback models',
      () {
    final original = sender('first', 'Alice', avatar: 'first-avatar');
    final other = sender('other', 'Bob');
    final directory = ChatHistorySenderDirectory()
      ..addPage([
        original,
        sender('', 'Empty'),
        sender('  ', 'Whitespace'),
        sender('first', 'Duplicate', avatar: 'duplicate-avatar'),
      ]);
    expect(directory.addPage([original]), isFalse);
    expect(directory.addPage([original, other]), isTrue);
    expect(ids(directory), ['first', 'other']);
    expect(identical(directory[0], original), isTrue);
    expect(identical(directory[1], other), isTrue);
  });

  test('public nicknames remain visible without affecting source order', () {
    final original = sender('winter', '秋备注', nickname: ' 冬 ');
    final directory = ChatHistorySenderDirectory()
      ..addPage([sender('autumn', '冬备注', nickname: '秋'), original]);
    expect(ids(directory), ['autumn', 'winter']);
    expect(directory[1].name, '冬');
    expect(directory[1].displayName, '秋备注');
    expect(identical(directory[1], original), isTrue);
  });

  test('appended pages retain existing positions including equal names', () {
    final source = List.generate(
        151,
        (index) => sender(
            'member-$index', ['Alice', '阿强', '冬', '秋', '123'][index % 5]));
    final directory = ChatHistorySenderDirectory()..addPage(source.take(50));
    final previous = ids(directory);
    directory.addPage(source.skip(40).take(60));
    expect(ids(directory).take(50), previous);
    directory.addPage(source.skip(100));
    expect(ids(directory), source.map((member) => member.userID));
  });

  test('clearing a query releases old rows and allows fresh models', () {
    final directory = ChatHistorySenderDirectory()
      ..addPage([sender('a', 'Alice'), sender('d', '冬')]);
    directory.clear();
    expect(directory.isEmpty, isTrue);
    final renamed = sender('d', '秋', avatar: 'new-avatar');
    directory.addPage([renamed]);
    expect(ids(directory), ['d']);
    expect(identical(directory[0], renamed), isTrue);
  });
}
