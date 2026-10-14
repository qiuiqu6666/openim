import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_history_loader_test.dart' show Harness, msg;

void main() {
  for (final end in [true, false]) {
    test('empty refresh isEnd=$end preserves rows and older cursor', () async {
      final cursors = <String?>[];
      final h = Harness(({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        if (cursors.length == 1) {
          return AdvancedMessage(messageList: [msg('old', 10), msg('last', 11)], isEnd: false);
        }
        if (cursors.length == 2) return AdvancedMessage(messageList: [], isEnd: end);
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
