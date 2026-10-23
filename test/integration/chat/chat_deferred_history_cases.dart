import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../support/chat/chat_entry_list.dart';
import '../../support/chat/chat_entry_sdk.dart';

Message _row(int n) => Message(
    clientMsgID: 'row-$n',
    seq: n,
    sendTime: n,
    sendID: 'peer',
    recvID: 'self',
    sessionType: ConversationType.single,
    contentType: MessageType.text,
    status: MessageStatus.succeeded,
    textElem: TextElem(content: 'row-$n'));

Future<void> _readOlder(WidgetTester tester) async {
  // Initial snapshots follow the latest page until the user explicitly reads history.
  await tester.drag(find.byType(ChatListView), const Offset(0, 160));
  await tester.pumpAndSettle();
}

void registerDeferredHistoryCases(
    {required ChatLogic Function() open,
    required List<EntryHistoryCall> Function() calls,
    required void Function(List<Message>) seed}) {
  testWidgets('drag pages through deferred history without the latest button',
      (tester) async {
    seed(List.generate(40, (i) => _row(i + 1)));
    final logic = open();
    await tester.pumpWidget(
        buildChatEntryList(logic, commonList: true, newerPaging: true));
    await tester.pump();
    await _readOlder(tester);
    calls().single.complete([_row(100)], isEnd: false);
    await tester.pump();
    await tester.pump();
    expect(logic.hasDeferredLatest, isTrue);
    expect(calls(), hasLength(1), reason: 'Layout alone must not fetch');

    await tester.drag(find.byType(ChatListView), const Offset(0, -400));
    await tester.pump();
    expect(calls(), hasLength(2));
    expect(calls().last.arguments['startClientMsgID'], 'row-40');
    calls().last.complete(List.generate(30, (i) => _row(i + 41)), isEnd: false);
    await tester.pumpAndSettle();
    expect(logic.messageList.last.clientMsgID, 'row-70');
    expect(logic.hasDeferredLatest, isTrue);
    expect(logic.messageList.any((m) => m.clientMsgID == 'row-100'), isFalse,
        reason: 'Do not splice the disconnected latest page into history');

    logic.scrollController
        .jumpTo(logic.scrollController.position.minScrollExtent + 200);
    await tester.pump();
    expect(calls(), hasLength(2), reason: 'Programmatic moves must not fetch');
    await tester.drag(find.byType(ChatListView), const Offset(0, -400));
    await tester.pump();
    expect(logic.historyNewerHasMore.value, isTrue);
    expect(logic.historyError.value, isNull);
    expect(calls(), hasLength(3));
    expect(calls().last.arguments['startClientMsgID'], 'row-70');
    calls().last.complete(List.generate(30, (i) => _row(i + 71)));
    await tester.pumpAndSettle();
    expect(logic.messageList.map((m) => m.seq),
        orderedEquals(List.generate(100, (i) => i + 1)));
    expect(logic.hasDeferredLatest, isFalse);
    expect(logic.viewingHistory.value, isFalse);
    expect(logic.historyNewerHasMore.value, isFalse);
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final gap in [false, true]) {
    for (final readingOlder in [false, true]) {
      testWidgets(
          'explicit history reading stays anchored; gap=$gap older=$readingOlder',
          (tester) async {
        seed(List.generate(40, (i) => _row(i + 1)));
        final logic = open();
        var visible = <String>[];
        await tester.pumpWidget(buildChatEntryList(logic,
            commonList: true, observeViewport: (ids, _) => visible = ids));
        await tester.pump();
        await _readOlder(tester);
        if (readingOlder) {
          logic.scrollController.jumpTo(160);
          await tester.pump();
        }
        final anchor = visible.first;
        final before = tester.getTopLeft(find.text(anchor));
        final page = gap
            ? List.generate(20, (i) => _row(101 + i))
            : List.generate(40, (i) => _row(21 + i));
        calls().single.complete(page, isEnd: false);
        await tester.pump();
        await tester.pump();
        expect(logic.messageList.length, 40);
        expect(logic.messageList.last.clientMsgID, 'row-40');
        expect(tester.getTopLeft(find.text(anchor)), before);
        expect(logic.hasDeferredLatest, isTrue);
        expect(logic.newMessages.showBackToBottom.value, isTrue);
        expect(logic.newMessages.unseenCount.value, 0,
            reason: 'A history page cannot prove the total number of arrivals');
        expect(calls(), hasLength(1),
            reason: 'Layout cannot auto-fetch or join the newer range');
        logic.scrollBottom(smooth: true);
        await tester.pump();
        expect(find.text(anchor), findsOneWidget,
            reason: 'Keep old rows readable while waiting for network');
        expect(calls(), hasLength(2));
        calls().last.complete(page, isEnd: false);
        await tester.pump();
        expect(logic.messageList.last.clientMsgID, gap ? 'row-120' : 'row-60');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump();
        await tester.pump();
        expect(logic.messageList.last.clientMsgID, gap ? 'row-120' : 'row-60');
        expect(logic.messageList.first.clientMsgID, gap ? 'row-101' : 'row-21');
        expect(logic.hasDeferredLatest, isFalse);
        expect(logic.viewingHistory.value, isFalse);
        await tester.pumpAndSettle();
        expectMessageInsideChatList(tester, gap ? 'row-120' : 'row-60');
        logic.onDelete();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final afterCommit in [false, true]) {
    testWidgets(
        'drag cancels pending return without rolling back committed latest; committed=$afterCommit',
        (tester) async {
      seed(List.generate(40, (i) => _row(i + 1)));
      final logic = open();
      await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
      await tester.pump();
      await _readOlder(tester);
      calls().single.complete([_row(100)], isEnd: false);
      await tester.pump();
      logic.scrollBottom(smooth: true);
      await tester.pump();
      if (afterCommit) {
        calls().last.complete([_row(100)], isEnd: false);
        await tester.pump();
        expect(logic.messageList.last.clientMsgID, 'row-100');
      }
      await tester.drag(find.byType(ChatListView), const Offset(0, 80));
      if (!afterCommit) calls().last.complete([_row(100)], isEnd: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(logic.messageList.last.clientMsgID,
          afterCommit ? 'row-100' : 'row-40');
      expect(logic.hasDeferredLatest, !afterCommit);
      logic.onDelete();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'failed explicit return preserves the painted window and can retry',
      (tester) async {
    seed(List.generate(40, (i) => _row(i + 1)));
    final logic = open();
    await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
    await tester.pump();
    await _readOlder(tester);
    calls().single.complete([_row(100)], isEnd: false);
    await tester.pump();
    logic.scrollBottom(smooth: true);
    await tester.pump();
    calls().last.result.completeError(StateError('offline'));
    await tester.pump();
    expect(logic.hasDeferredLatest, isTrue);
    expect(find.byType(ChatListView), findsOneWidget);
    expect(logic.messageList.last.clientMsgID, 'row-40');
    logic.scrollBottom(smooth: true);
    await tester.pump();
    calls().last.complete([_row(100)], isEnd: false);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.single.clientMsgID, 'row-100');
    expect(logic.hasDeferredLatest, isFalse);
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion returns only on request without a fade delay',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    seed(List.generate(40, (i) => _row(i + 1)));
    final logic = open();
    await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
    await tester.pump();
    await _readOlder(tester);
    calls().single.complete([_row(100)], isEnd: false);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'row-40');
    logic.scrollBottom(smooth: true);
    await tester.pump();
    calls().last.complete([_row(100)], isEnd: false);
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.single.clientMsgID, 'row-100');
    expect(find.byType(ChatListView), findsOneWidget);
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
