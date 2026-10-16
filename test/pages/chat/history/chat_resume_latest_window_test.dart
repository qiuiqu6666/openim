import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'chat_deferred_paging_test.dart' show row;
import 'message_window_ingress_test.dart' show window;

void main() {
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);
  for (final readingHistory in [false, true]) {
    testWidgets('resume across a large gap / readingHistory=$readingHistory',
        (tester) async {
      var target = 11;
      final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () => ConversationInfo(conversationID: 'chat'),
        fetch: ({required count, startMsg}) async => AdvancedMessage(
          messageList: [row(target - 1), row(target)],
          isEnd: false,
          window: window(target),
        ),
        fetchNewer: ({required count, startMsg}) async =>
            AdvancedMessage(messageList: [row(12)], isEnd: false),
        preserveReading: () => readingHistory,
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {},
      );
      timeline.initialize(prefetch: false);
      await timeline.loadOlder();
      timeline.recordPaintedRows(['m10', 'm11']);
      target = 101; // More than one page arrived while the app was suspended.
      await timeline.refresh();
      expect(timeline.latestDeferred.value, readingHistory);
      expect(timeline.viewingHistory.value, readingHistory);
      expect(timeline.messageList.map((m) => m.seq),
          readingHistory ? [10, 11] : [100, 101]);
      if (readingHistory) {
        await timeline.refresh();
        expect(timeline.messageList.map((m) => m.seq), [10, 11]);
        await timeline.returnToLatest();
        expect(timeline.messageList.map((m) => m.seq), [100, 101]);
      }
      timeline.appendIncoming(row(102), trim: true);
      await tester.pump(const Duration(milliseconds: 16));
      expect(timeline.messageList.map((m) => m.seq), [100, 101, 102],
          reason: 'Live delivery must continue without closing the chat route');
      timeline.close();
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
