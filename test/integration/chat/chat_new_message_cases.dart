import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim_common/openim_common.dart';

typedef MountChatScenario = Future<ChatLogic> Function(
  WidgetTester tester, {
  double Function(Message)? rowHeight,
  void Function(List<String>, double)? observeViewport,
});

/// Registers cross-module cases using the entry test's existing SDK fixture.
void registerChatNewMessageCases({
  required MountChatScenario mountChat,
  required void Function(Message) receive,
  required Message Function(String, int) createMessage,
}) {
  testWidgets('estimated latest edge does not erase unseen SDK arrivals',
      (tester) async {
    final heights = <String, double>{};
    final receivedIDs = <String>{};
    final readIDs = <String>{};
    double? reportedDistance;
    final logic = await mountChat(tester,
        rowHeight: (message) => heights[message.clientMsgID] ?? 48,
        observeViewport: (ids, distance) {
          readIDs.addAll(ids.where(receivedIDs.contains));
          reportedDistance = distance;
        });
    final controller = logic.scrollController;
    controller.jumpTo(500);
    await tester.pumpAndSettle();
    for (var index = 999; index >= 0; index--) {
      final id = 'new-$index';
      heights[id] = index >= 990 ? 25 : 200;
      receivedIDs.add(id);
      receive(createMessage(id, 1030 - index));
    }
    expect(logic.newMessages.unseenCount.value, 1000);
    await tester.pumpAndSettle();
    expect(logic.newMessages.unseenCount.value, 1000);
    final estimatedMinimum = controller.position.minScrollExtent;

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ChatListView)));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.moveBy(Offset(0, estimatedMinimum - controller.offset));
    // This controller notification is before new rows are laid out: its
    // apparently-zero distance must not be treated as a painted latest edge.
    expect(controller.offset - controller.position.minScrollExtent,
        lessThanOrEqualTo(1));
    expect(logic.newMessages.unseenCount.value, 1000);
    expect(logic.newMessages.awayFromLatest.value, isTrue);

    heights['new-extra'] = 200;
    receivedIDs.add('new-extra');
    receive(createMessage('new-extra', 1031));
    expect(logic.newMessages.unseenCount.value, 1001);
    expect(controller.offset, estimatedMinimum);
    await tester.pumpAndSettle();
    expect(controller.position.minScrollExtent, lessThan(estimatedMinimum));
    expect(reportedDistance, greaterThan(1));
    expect(controller.offset - controller.position.minScrollExtent,
        greaterThan(1));
    expect(readIDs, isNot(contains('new-0')));
    expect(readIDs, isNot(contains('new-extra')));
    expect(logic.newMessages.unseenCount.value, 1001 - readIDs.length);
    expect(logic.newMessages.unseenCount.value, greaterThan(0));
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(logic.scrollingCacheMessageList, isEmpty);
    // The first refined viewport can contain two partial 200px rows. Continue
    // the same drag until one entire bubble is visible before expecting a read.
    final previouslyRead = readIDs.length;
    await gesture.moveBy(const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(readIDs.length, greaterThan(previouslyRead));
    expect(logic.newMessages.unseenCount.value, 1001 - readIDs.length);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(readIDs, isNot(contains('new-extra')));
    await gesture.up();
    await tester.pumpAndSettle();
    logic.onDelete();
  });
}
