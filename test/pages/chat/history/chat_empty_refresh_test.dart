import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_history_loader_test.dart' show Harness, msg;

void main() {
  test('empty first read preserves seed and retries without confirming it',
      () async {
    var reads = 0;
    final h = Harness(({required count, startMsg}) async => ++reads == 1
        ? AdvancedMessage(messageList: [], isEnd: true)
        : AdvancedMessage(messageList: [msg('latest', 12)], isEnd: true));
    addTearDown(h.loader.close);
    h.values = [msg('seed', 11)];
    await h.loader.loadOlder();
    expect(h.values.single.clientMsgID, 'seed');
    expect(h.loader.loaded, isFalse);
    expect(h.loader.error, isNotNull);
    await h.loader.retry();
    expect(h.values.single.clientMsgID, 'latest');
    expect(h.loader.loaded, isTrue);
    expect(h.loader.error, isNull);
  });

  test('empty explicit latest replacement keeps window and reports retry',
      () async {
    var reads = 0;
    final h = Harness(({required count, startMsg}) async => ++reads == 1
        ? AdvancedMessage(messageList: [msg('last', 11)], isEnd: true)
        : AdvancedMessage(messageList: [], isEnd: true));
    addTearDown(h.loader.close);
    await h.loader.loadOlder();
    expect(await h.loader.returnToLatest(), isFalse);
    expect(h.values.single.clientMsgID, 'last');
    expect(h.loader.error, isNotNull);
  });

  for (final end in [true, false]) {
    test('empty refresh isEnd=$end preserves rows and older cursor', () async {
      final cursors = <String?>[];
      final h = Harness(({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        if (cursors.length == 1) {
          return AdvancedMessage(
              messageList: [msg('old', 10), msg('last', 11)], isEnd: false);
        }
        if (cursors.length == 2) {
          return AdvancedMessage(messageList: [], isEnd: end);
        }
        return AdvancedMessage(messageList: [msg('older', 9)], isEnd: true);
      });
      addTearDown(h.loader.close);
      await h.loader.loadOlder();
      await h.loader.refresh();
      expect(h.values.map((m) => m.clientMsgID), ['old', 'last']);
      expect(h.loader.hasMore, isTrue);
      await h.loader.loadOlder();
      expect(cursors, [null, null, 'old']);
      expect(h.values.map((m) => m.clientMsgID), ['older', 'old', 'last']);
    });
  }

  test('explicit clear still wins over an empty refresh', () async {
    var reads = 0;
    final h = Harness(({required count, startMsg}) async => ++reads == 1
        ? AdvancedMessage(messageList: [msg('last', 11)], isEnd: true)
        : AdvancedMessage(messageList: [], isEnd: true));
    addTearDown(h.loader.close);
    await h.loader.loadOlder();
    h.loader.clear();
    h.values.clear();
    await h.loader.refresh();
    expect(h.values, isEmpty);
  });
}
