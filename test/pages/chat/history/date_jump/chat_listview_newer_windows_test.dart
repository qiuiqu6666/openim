import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim_common/openim_common.dart';

Message _message(int time) => Message(
      clientMsgID: 'm-$time',
      sendTime: time,
      seq: time,
      contentType: MessageType.text,
      status: MessageStatus.succeeded,
    );

List<Message> _range(int start, int count) =>
    List.generate(count, (index) => _message(start + index));

Future<void> _reachNewerEdge(
    WidgetTester tester, ScrollController scroll) async {
  scroll.jumpTo(scroll.position.minScrollExtent + 200);
  await tester.pumpAndSettle();
  scroll.jumpTo(scroll.position.minScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  for (final failFirstPage in [false, true]) {
    testWidgets(
        'second date window loads newer after the first window '
        '${failFirstPage ? 'failed' : 'reached latest'}', (tester) async {
      final scroll = ScrollController();
      final pagedCursors = <String?>[];
      var pagingCalls = 0;
      final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () => ConversationInfo(conversationID: 'chat'),
        isClosed: () => false,
        onFirstPage: () {},
        onFirstLoaded: () {},
        captureOffset: () => scroll.hasClients ? scroll.offset : 0,
        restoreOffset: (_) {},
        fetch: ({required count, startMsg}) async => AdvancedMessage(
          messageList: startMsg == null
              ? _range(200, 30)
              : _range(startMsg.sendTime! - count, count),
          isEnd: false,
        ),
        fetchNewer: ({required count, startMsg}) async {
          final time = startMsg!.sendTime!;
          final seeking = time == 50 || time == 100;
          if (!seeking) pagedCursors.add(startMsg.clientMsgID);
          return AdvancedMessage(
            messageList: _range(time + 1, count),
            isEnd: !seeking,
          );
        },
      );
      timeline.messageList.value = _range(200, 30);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        timeline.close();
        scroll.dispose();
      });
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: Obx(() {
                final ids = timeline.messageList.reversed
                    .map((message) => message.clientMsgID!)
                    .toList();
                return ChatListView(
                  controller: scroll,
                  itemCount: ids.length,
                  messageIDs: ids,
                  loadOnInit: false,
                  hasMore: false,
                  enabledScrollTopLoad: timeline.newerHasMore.value,
                  onScrollToTopLoad: () async {
                    pagingCalls++;
                    if (failFirstPage && pagingCalls == 1) {
                      throw StateError('first window newer paging failed');
                    }
                    return timeline.loadNewer();
                  },
                  findChildIndexCallback: (key) {
                    final index = ids.indexOf((key as ValueKey<String>).value);
                    return index < 0 ? null : index;
                  },
                  itemBuilder: (_, index) => SizedBox(
                    key: ValueKey(ids[index]),
                    height: 60,
                    child: Text(ids[index]),
                  ),
                );
              }),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(await timeline.jumpTo(_message(50)), isTrue);
      await tester.pumpAndSettle();
      expect(timeline.newerHasMore.value, isTrue);
      await _reachNewerEdge(tester, scroll);
      expect(pagingCalls, 1);
      if (failFirstPage) {
        expect(find.byType(TextButton), findsOneWidget);
      } else {
        expect(timeline.newerHasMore.value, isFalse);
        expect(pagedCursors, ['m-70']);
      }

      expect(await timeline.returnToLatest(), isTrue);
      await tester.pumpAndSettle();
      expect(timeline.newerHasMore.value, isFalse);
      expect(await timeline.jumpTo(_message(100)), isTrue);
      await tester.pumpAndSettle();
      expect(timeline.newerHasMore.value, isTrue);
      expect(find.byType(TextButton), findsNothing);
      await _reachNewerEdge(tester, scroll);
      expect(pagingCalls, 2);
      expect(pagedCursors.last, 'm-120');
      expect(
          timeline.messageList.any((message) => message.clientMsgID == 'm-160'),
          isTrue);
      expect(timeline.newerHasMore.value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
