import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/conversation/summary/pinned_group_order.dart';

ConversationInfo group(String id, {bool pinned = true, int time = 0}) =>
    ConversationInfo(
        conversationID: id,
        conversationType: 3,
        isPinned: pinned,
        latestMsgSendTime: time);

void main() {
  test('new messages and SDK snapshots preserve the saved pin order', () {
    final saved = <List<String>>[];
    final order = PinnedGroupOrder([], save: saved.add);
    order.apply([group('a'), group('b')]);
    final rows = order.apply([group('b', time: 999), group('a')]);
    expect(rows.map((r) => r.conversationID), ['a', 'b']);
    expect(rows.last.latestMsgSendTime, 999);
    expect(saved.length, 1);
    final restored = PinnedGroupOrder(saved.last, save: saved.add);
    expect(
        restored.apply([group('b'), group('a')]).map((r) => r.conversationID),
        ['a', 'b']);
  });

  test('new pins append; unpin then repin moves to the end', () {
    final order = PinnedGroupOrder(['a', 'b'], save: (_) {});
    order.apply([group('a', pinned: false)]);
    expect(
        order.apply([group('a'), group('b'), group('c')]).map(
            (r) => r.conversationID),
        ['b', 'a', 'c']);
  });

  test('partial pages retain missing ranks and leave unpinned rows untouched',
      () {
    final order = PinnedGroupOrder(['a', 'b'], save: (_) {});
    order.apply([group('b')]);
    final recent = group('recent', pinned: false, time: 100);
    final older = group('older', pinned: false, time: 10);
    expect(
        order.apply([group('b'), group('a'), recent, older]).map(
            (r) => r.conversationID),
        ['a', 'b', 'recent', 'older']);
  });
}
