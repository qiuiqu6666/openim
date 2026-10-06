import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_directory.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';
import 'package:openim/pages/contacts/directory/contact_directory_indexer.dart';

ChatHistorySender sender(String id, String name,
        {String? avatar, String? nickname}) =>
    ChatHistorySender(
        userID: id, displayName: name, faceURL: avatar, nickname: nickname);

void main() {
  test('Chinese and English names use shared letter groups with # last', () {
    final source = [
      sender('autumn', '秋'),
      sender('number', '123'),
      sender('winter', '冬'),
      sender('alice', 'alice'),
      sender('symbol', '!用户'),
      sender('bob', 'Bob'),
    ];
    final rows = buildChatHistorySenderDirectory(source);
    expect(rows.map((row) => row.getSuspensionTag()),
        ['A', 'B', 'D', 'Q', '#', '#']);
    expect(
        rows
            .singleWhere((row) => row.sender.userID == 'winter')
            .index
            .namePinyin,
        'DONG');
    expect(
        rows
            .singleWhere((row) => row.sender.userID == 'autumn')
            .index
            .namePinyin,
        'QIU');
    expect(rows.map((row) => row.isShowSuspension),
        [true, true, true, true, true, false]);
    expect(rows.every((row) => row.isShowSuspension == row.index.showHeader),
        isTrue);
  });

  test('duplicates and empty IDs are removed without replacing callback models',
      () {
    final original = sender('first', 'Alice', avatar: 'first-avatar');
    final other = sender('other', 'Bob');
    final rows = buildChatHistorySenderDirectory([
      original,
      sender('', 'Empty'),
      sender('  ', 'Whitespace'),
      sender('first', 'Duplicate', avatar: 'duplicate-avatar'),
      other,
    ]);
    expect(rows.map((row) => row.sender.userID), ['first', 'other']);
    expect(identical(rows.first.sender, original), isTrue);
    expect(identical(rows.last.sender, other), isTrue);
  });

  test('unchanged display names reuse cached pinyin but keep fresh sender data',
      () {
    final original = sender('winter', '冬', avatar: 'old-avatar');
    final cached = ChatHistorySenderRow(
      sender: original,
      index: const ContactNameIndex(
        userID: 'winter',
        displayName: '冬',
        namePinyin: 'CACHED DONG',
        tagIndex: 'D',
      ),
    );
    final updated = sender('winter', '冬', avatar: 'new-avatar');
    final rows = buildChatHistorySenderDirectory([updated], previous: [cached]);
    expect(rows.single.index.namePinyin, 'CACHED DONG');
    expect(rows.single.getSuspensionTag(), 'D');
    expect(rows.single.isShowSuspension, isTrue);
    expect(identical(rows.single.sender, updated), isTrue);
    expect(rows.single.sender.faceURL, 'new-avatar');
  });

  test('renaming an existing sender invalidates its old pinyin and section',
      () {
    final previous = buildChatHistorySenderDirectory([sender('person', '冬')]);
    final rows = buildChatHistorySenderDirectory([sender('person', '秋')],
        previous: previous);
    expect(rows.single.getSuspensionTag(), 'Q');
    expect(rows.single.index.namePinyin, 'QIU');
    expect(rows.single.index.displayName, '秋');
    expect(previous.single.getSuspensionTag(), 'D');
    expect(previous.single.index.displayName, '冬');
  });

  test(
      'public nicknames determine directory groups instead of conversation aliases',
      () {
    final original = sender('winter', '秋备注', nickname: ' 冬 ');
    final rows = buildChatHistorySenderDirectory([
      sender('autumn', '冬备注', nickname: '秋'),
      original,
    ]);
    expect(rows.map((row) => row.getSuspensionTag()), ['D', 'Q']);
    expect(rows.first.index.displayName, '冬');
    expect(identical(rows.first.sender, original), isTrue);
    expect(rows.first.sender.displayName, '秋备注');
  });

  test(
      'a nickname change invalidates cached pinyin even when the alias is unchanged',
      () {
    final previous = buildChatHistorySenderDirectory([
      sender('person', '备注', nickname: '冬'),
    ]);
    final rows = buildChatHistorySenderDirectory([
      sender('person', '备注', nickname: '秋'),
    ], previous: previous);
    expect(rows.single.index.namePinyin, 'QIU');
    expect(rows.single.getSuspensionTag(), 'Q');
    expect(rows.single.index.displayName, '秋');
  });

  test('an alias change retains the nickname cache and returns the new sender',
      () {
    final cached = ChatHistorySenderRow(
      sender: sender('person', '原备注', nickname: '冬'),
      index: const ContactNameIndex(
        userID: 'person',
        displayName: '冬',
        namePinyin: 'CACHED DONG',
        tagIndex: 'D',
      ),
    );
    final updated = sender('person', '新备注', nickname: ' 冬 ');
    final rows = buildChatHistorySenderDirectory([updated], previous: [cached]);
    expect(rows.single.index.namePinyin, 'CACHED DONG');
    expect(identical(rows.single.sender, updated), isTrue);
    expect(rows.single.sender.displayName, '新备注');
  });

  test('appended pages preserve the shared within-group ordering and headers',
      () {
    final source = List.generate(
        151,
        (index) => sender(
            'member-$index', ['Alice', '阿强', '冬', '秋', '123'][index % 5]));
    final previous = buildChatHistorySenderDirectory(source.take(50));
    final rows = buildChatHistorySenderDirectory(source, previous: previous);
    final expected = buildContactNameIndex([
      for (final member in source)
        ContactNameIndex(
            userID: member.userID, displayName: member.displayName),
    ]);
    expect(rows.map((row) => row.sender.userID),
        expected.map((index) => index.userID));
    expect(rows.map((row) => row.isShowSuspension),
        expected.map((index) => index.showHeader));
    expect(rows.map((row) => row.index.namePinyin),
        expected.map((index) => index.namePinyin));
  });

  test('removed groups do not retain stale section headers or senders', () {
    final previous = buildChatHistorySenderDirectory([
      sender('a', 'Alice'),
      sender('d-first', '冬一'),
      sender('d-second', '冬二'),
    ]);
    final rows = buildChatHistorySenderDirectory([sender('d-second', '冬二')],
        previous: previous);
    expect(rows.single.sender.userID, 'd-second');
    expect(rows.single.isShowSuspension, isTrue);
    expect(buildChatHistorySenderDirectory([], previous: previous), isEmpty);
  });
}
