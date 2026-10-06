import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/directory/contact_directory_indexer.dart';
import 'package:openim_common/openim_common.dart';

ContactNameIndex _name(String id, String name) =>
    ContactNameIndex(userID: id, displayName: name);

void main() {
  test('worker groups Chinese and Latin names and marks headers', () {
    final source = [
      _name('z', '张三'),
      _name('a1', 'Alice'),
      _name('symbol', '😀'),
      _name('a2', '阿强'),
      _name('empty', ' '),
    ];
    final indexed = buildContactNameIndex(source);

    final legacy = IMUtils.convertToAZList([
      for (final name in source)
        ISUserInfo.fromJson(
            {'userID': name.userID, 'nickname': name.displayName}),
    ]).cast<ISUserInfo>();
    expect(indexed.map((name) => name.userID),
        legacy.map((friend) => friend.userID));
    expect(indexed.map((name) => name.tagIndex), ['A', 'A', 'Z', '#', '#']);
    expect(indexed.map((name) => name.showHeader),
        [true, false, true, true, false]);
    expect(indexed[2].namePinyin, 'ZHANG SAN');
    expect(indexed.singleWhere((name) => name.userID == 'empty').namePinyin,
        isNull);
    expect(source.every((name) => name.tagIndex == null), isTrue);
  });

  test('large same-letter directories retain the exact legacy sort order', () {
    final names = List.generate(
        501,
        (i) => _name(
            'friend$i',
            [
              'Alice$i',
              '阿强$i',
              'Zed$i',
              '张三$i',
              '😀$i',
            ][i % 5]));
    final legacy = IMUtils.convertToAZList([
      for (final name in names)
        ISUserInfo.fromJson(
            {'userID': name.userID, 'nickname': name.displayName}),
    ]).cast<ISUserInfo>();
    final indexed = buildContactNameIndex(names);

    expect(indexed.map((name) => name.userID),
        legacy.map((friend) => friend.userID));
    expect(indexed.map((name) => name.namePinyin),
        legacy.map((friend) => friend.namePinyin));
    expect(indexed.map((name) => name.showHeader),
        legacy.map((friend) => friend.isShowSuspension));
  });

  test('unchanged names reuse pinyin while display-name changes invalidate it',
      () async {
    final requests = <List<ContactNameIndex>>[];
    final indexer = ContactDirectoryIndexer(worker: (names) async {
      requests.add(names);
      return buildContactNameIndex(names);
    });
    addTearDown(indexer.close);
    await indexer.build([_name('one', '王五'), _name('two', 'Alice')]);
    await indexer.build([_name('one', '王五'), _name('two', '张三')]);

    expect(requests.first.every((name) => name.tagIndex == null), isTrue);
    expect(requests.last[0].tagIndex, 'W');
    expect(requests.last[0].namePinyin, 'WANG WU');
    expect(requests.last[1].tagIndex, isNull);
  });

  test('deleted contacts leave the pinyin cache', () async {
    final requests = <List<ContactNameIndex>>[];
    final indexer = ContactDirectoryIndexer(worker: (names) async {
      requests.add(names);
      return buildContactNameIndex(names);
    });
    addTearDown(indexer.close);
    await indexer.build([_name('deleted', 'Alice')]);
    await indexer.build([]);
    await indexer.build([_name('deleted', 'Alice')]);

    expect(requests.last.single.tagIndex, isNull);
  });

  test('older worker completion cannot replace the latest name cache',
      () async {
    final requests = <List<ContactNameIndex>>[];
    final workers = <Completer<List<ContactNameIndex>>>[];
    final indexer = ContactDirectoryIndexer(worker: (names) {
      requests.add(names);
      final worker = Completer<List<ContactNameIndex>>();
      workers.add(worker);
      return worker.future;
    });
    addTearDown(indexer.close);
    final old = indexer.build([_name('same', 'Alice')]);
    final latest = indexer.build([_name('same', '张三')]);
    workers[1].complete(buildContactNameIndex(requests[1]));
    expect((await latest)?.single.tagIndex, 'Z');
    workers[0].complete(buildContactNameIndex(requests[0]));
    expect(await old, isNull);
    final reused = indexer.build([_name('same', '张三')]);
    expect(requests.last.single.tagIndex, 'Z');
    workers.last.complete(buildContactNameIndex(requests.last));
    await reused;
  });

  test('close discards the late worker and prevents any new work', () async {
    var calls = 0;
    final worker = Completer<List<ContactNameIndex>>();
    final indexer = ContactDirectoryIndexer(worker: (names) {
      calls++;
      return worker.future;
    });
    final pending = indexer.build([_name('one', 'Alice')]);
    indexer.close();
    worker.complete(buildContactNameIndex([_name('one', 'Alice')]));

    expect(await pending, isNull);
    expect(await indexer.build([_name('two', 'Bob')]), isNull);
    expect(calls, 1);
  });

  test('a failed worker can be retried without caching a partial result',
      () async {
    var calls = 0;
    final indexer = ContactDirectoryIndexer(worker: (names) async {
      if (calls++ == 0) throw StateError('worker unavailable');
      expect(names.single.tagIndex, isNull);
      return buildContactNameIndex(names);
    });
    addTearDown(indexer.close);
    await expectLater(indexer.build([_name('one', 'Alice')]), throwsStateError);
    expect(
        (await indexer.build([_name('one', 'Alice')]))?.single.tagIndex, 'A');
  });

  test('default worker indexes a real directory through the compute boundary',
      () async {
    final indexer = ContactDirectoryIndexer();
    addTearDown(indexer.close);
    final indexed = await indexer.build(List.generate(
        1000, (i) => _name('friend$i', i.isEven ? '张三$i' : 'Alice$i')));

    expect(indexed, hasLength(1000));
    expect(indexed!.first.tagIndex, 'A');
    expect(indexed.last.tagIndex, 'Z');
    expect(indexed.where((name) => name.showHeader), hasLength(2));
  });
}
