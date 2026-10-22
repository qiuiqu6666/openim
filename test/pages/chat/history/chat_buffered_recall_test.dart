import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';

void main() {
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  for (final type in [MessageType.picture, MessageType.text]) {
    test('buffered $type is normalized when later history confirms recall', () {
      final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () => ConversationInfo(conversationID: 'chat'),
        fetch: ({required count, startMsg}) async => AdvancedMessage(),
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {},
      );
      addTearDown(timeline.close);
      timeline.bufferIncoming(Message(
          clientMsgID: 'old',
          contentType: type,
          pictureElem: type == MessageType.picture ? PictureElem() : null));
      // History/prewarming can confirm recall without a second live event.
      ChatHistoryCache.write('me', 'chat', [
        Message(
            clientMsgID: 'old',
            contentType: MessageType.revokeMessageNotification)
      ]);
      timeline.flushBuffered();
      expect(timeline.messageList.single.contentType,
          MessageType.revokeMessageNotification);
      expect(timeline.messageList.single.pictureElem, isNull);
      expect(timeline.scrollingCacheMessageList, isEmpty);
    });
  }
}
