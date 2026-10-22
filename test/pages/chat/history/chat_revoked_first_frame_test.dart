import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim/services/chat_revocation_notice.dart';

Message picture() => Message(
    clientMsgID: 'photo',
    seq: 1,
    sendTime: 1,
    status: MessageStatus.succeeded,
    contentType: MessageType.picture,
    pictureElem: PictureElem());
Message notice() => ChatRevocationNotice.replace(
    picture(), RevokedInfo(clientMsgID: 'photo', revokerID: 'peer'));

void main() {
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  testWidgets(
      'recall before local query, stale paging and reconnect refresh never publish a picture',
      (tester) async {
    final local = Completer<List<Message>>();
    final initial = Completer<AdvancedMessage>();
    var calls = 0;
    final timeline = ChatTimelineController(
      accountID: 'me',
      currentAccountID: () => 'me',
      conversation: () => ConversationInfo(conversationID: 'chat'),
      fetchDisplaySnapshot: () => local.future,
      fetch: ({required count, startMsg}) => ++calls == 1
          ? initial.future
          : Future.value(
              AdvancedMessage(messageList: [picture()], isEnd: true)),
      isClosed: () => false,
      onFirstPage: () {},
      captureOffset: () => 0,
      restoreOffset: (_) {},
      onFirstLoaded: () {},
    );
    final published = <int?>[];
    final worker = ever(timeline.messageList, (rows) {
      published.addAll(rows.map((row) => row.contentType));
    });
    addTearDown(() {
      worker.dispose();
      timeline.close();
    });
    timeline.initialize();
    ChatHistoryCache.revokeMessage('me', RevokedInfo(clientMsgID: 'photo'));
    local.complete([picture()]);
    await tester.pumpWidget(MaterialApp(
        home: Obx(() => Text(timeline.messageList
                .any((row) => row.contentType == MessageType.picture)
            ? '原图片'
            : '安全状态'))));
    expect(find.text('原图片'), findsNothing);
    initial.complete(AdvancedMessage(messageList: [picture()], isEnd: false));
    await tester.pump();
    await timeline.loadOlder();
    await tester.pump();
    await timeline.refresh();
    await tester.pump();
    expect(find.text('原图片'), findsNothing);
    expect(published, isNotEmpty);
    expect(published, isNot(contains(MessageType.picture)));
    expect(timeline.messageList.single.contentType,
        MessageType.revokeMessageNotification);
    timeline.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('revoked history wins over an old duplicate in either merge order', () {
    for (final rows in [
      [notice(), picture()],
      [picture(), notice()]
    ]) {
      final result = ChatHistoryLoader.merge(rows).single;
      expect(result.contentType, MessageType.revokeMessageNotification);
      expect(result.pictureElem, isNull);
    }
  });

  test('late incoming rows and quick route reentry preserve known recall',
      () async {
    ChatHistoryCache.write('me', 'chat', [notice()]);
    for (var entry = 0; entry < 2; entry++) {
      final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () => ConversationInfo(conversationID: 'chat'),
        fetch: ({required count, startMsg}) async =>
            AdvancedMessage(messageList: [picture()], isEnd: true),
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {},
      );
      timeline.appendIncoming(picture(), trim: false);
      timeline.bufferIncoming(picture());
      expect(timeline.messageList.single.pictureElem, isNull);
      expect(timeline.messageList.single.contentType,
          MessageType.revokeMessageNotification);
      expect(timeline.scrollingCacheMessageList.single.contentType,
          MessageType.revokeMessageNotification);
      timeline.close();
    }
  });

  test('normal pictures remain immediately available and accounts are isolated',
      () {
    ChatHistoryCache.write('other', 'chat', [notice()]);
    ChatHistoryCache.write('me', 'chat', [picture()]);
    expect(ChatHistoryCache.read('me', 'chat').single.contentType,
        MessageType.picture);
    expect(ChatHistoryCache.read('me', 'chat').single.pictureElem, isNotNull);
  });

  for (final viaCallback in [false, true]) {
    testWidgets(
        'first frame and delayed history stay revoked callback=$viaCallback',
        (tester) async {
      if (viaCallback) {
        ChatHistoryCache.revokeMessage('me', RevokedInfo(clientMsgID: 'photo'));
      } else {
        // A previous history read confirmed recall without a live callback.
        ChatHistoryCache.write('me', 'chat', [notice()]);
      }
      // A pending prefetch/old route completes after that confirmation.
      ChatHistoryCache.write('me', 'chat', [picture()]);
      final remote = Completer<AdvancedMessage>();
      final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () =>
            ConversationInfo(conversationID: 'chat', latestMsg: picture()),
        fetch: ({required count, startMsg}) => remote.future,
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {},
      );
      final published = <int?>[];
      final worker = ever(timeline.messageList, (rows) {
        published.addAll(rows.map((row) => row.contentType));
      });
      addTearDown(() {
        worker.dispose();
        timeline.close();
      });
      timeline.initialize();
      await tester.pumpWidget(MaterialApp(
          home: Obx(() => Column(children: [
                for (final row in timeline.messageList)
                  Text(
                      row.contentType == MessageType.revokeMessageNotification
                          ? '撤回了一条消息'
                          : '原图片',
                      key: ValueKey(row.clientMsgID)),
              ]))));
      expect(find.text('原图片'), findsNothing);
      expect(find.text('撤回了一条消息'), findsOneWidget);
      remote.complete(AdvancedMessage(messageList: [picture()], isEnd: true));
      await tester.pump();
      expect(find.text('原图片'), findsNothing);
      expect(published, isNot(contains(MessageType.picture)));
      timeline.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
