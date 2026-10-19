import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/updates/conversation_update_buffer.dart';

void main() {
  testWidgets(
      'hidden bursts merge, returning view publishes latest immediately',
      (tester) async {
    final published = <List<ConversationInfo>>[];
    final buffer = ConversationUpdateBuffer(
        publish: published.add, delay: () => const Duration(milliseconds: 80));
    final owner = Object();
    buffer.setViewActive(owner, false);
    for (var i = 0; i < 10; i++) {
      buffer.add([ConversationInfo(conversationID: 'c', unreadCount: i)]);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(published, isEmpty);
    buffer.setViewActive(owner, true);
    expect(published, isEmpty, reason: 'No publication during widget build');
    await tester.pump(Duration.zero);
    expect(published.single.single.unreadCount, 9);
    buffer.close();
  });

  testWidgets('hidden work has bounded delay and explicit reads can flush',
      (tester) async {
    final published = <List<ConversationInfo>>[];
    final buffer = ConversationUpdateBuffer(
        publish: published.add, delay: () => const Duration(milliseconds: 80));
    buffer.setViewActive(Object(), false);
    for (var i = 0; i < 20; i++) {
      buffer.add([ConversationInfo(conversationID: 'c', unreadCount: i)]);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(published.length, 2, reason: 'Continuous traffic must not starve');
    expect(published.last.single.unreadCount, 19);
    buffer.add([ConversationInfo(conversationID: 'c', unreadCount: 21)]);
    buffer.flush();
    expect(published.last.single.unreadCount, 21);
    buffer.close();
  });

  testWidgets('visible consumers combine and background work is coalesced',
      (tester) async {
    final published = <List<ConversationInfo>>[];
    final buffer = ConversationUpdateBuffer(
        publish: published.add, delay: () => const Duration(milliseconds: 80));
    final main = Object(), archive = Object();
    buffer.setViewActive(main, true);
    buffer.setViewActive(archive, false);
    buffer.add([ConversationInfo(conversationID: 'a')]);
    await tester.pump(const Duration(milliseconds: 80));
    expect(published.length, 1);
    buffer.setForeground(false);
    buffer.add([ConversationInfo(conversationID: 'b')]);
    await tester.pump(const Duration(milliseconds: 80));
    expect(published.length, 1);
    buffer.setForeground(true);
    await tester.pump(Duration.zero);
    expect(published.length, 2);
    buffer.removeView(main);
    buffer.add([ConversationInfo(conversationID: 'removed')]);
    buffer.remove('removed');
    buffer.close();
    await tester.pump(const Duration(seconds: 2));
    expect(published.length, 2);
  });

  testWidgets(
      'burst publishes latest per ID once; deletion and close cancel pending work',
      (tester) async {
    final published = <List<ConversationInfo>>[];
    final buffer = ConversationUpdateBuffer(
        publish: published.add, delay: () => const Duration(milliseconds: 16));
    for (var i = 0; i < 10000; i++) {
      buffer.add(
          [ConversationInfo(conversationID: 'c${i % 100}', unreadCount: i)]);
    }
    buffer.remove('c0');
    expect(published, isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    expect(published.length, 1);
    expect(published.single.length, 99);
    expect(published.single.last.unreadCount, 9999);
    buffer.add([ConversationInfo(conversationID: 'late')]);
    buffer.close();
    await tester.pump(const Duration(milliseconds: 16));
    expect(published.length, 1);
  });
}
