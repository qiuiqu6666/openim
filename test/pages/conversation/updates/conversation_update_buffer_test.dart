import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/updates/conversation_update_buffer.dart';

void main() {
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
