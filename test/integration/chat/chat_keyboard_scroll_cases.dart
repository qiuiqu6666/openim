import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim_common/openim_common.dart';

void registerChatKeyboardScrollCases({
  required Future<ChatLogic> Function(WidgetTester) mountChat,
  required void Function(Message) receive,
  required Message Function(String, int) createMessage,
}) {
  testWidgets('input tap returns smoothly while opening and retaining keyboard',
      (tester) async {
    final logic = await mountChat(tester);
    logic.scrollController.jumpTo(900);
    await tester.pumpAndSettle();
    receive(createMessage('keyboard-new', 100));
    await tester.pumpAndSettle();
    expect(logic.newMessages.unseenCount.value, 1);
    final original = logic.scrollController.offset;

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump();
    expect(logic.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pump(const Duration(milliseconds: 80));
    expect(logic.scrollController.offset, lessThan(original));
    expect(logic.scrollController.offset,
        greaterThan(logic.scrollController.position.minScrollExtent + 1));
    expect(logic.focusNode.hasFocus, isTrue);
    expect(logic.newMessages.unseenCount.value, 1);

    // Simulate the keyboard's progressive viewport resize during the return.
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 60));
    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    await tester.pumpAndSettle();
    expect(logic.scrollController.offset,
        closeTo(logic.scrollController.position.minScrollExtent, 1));
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    logic.onDelete();
  });

  testWidgets('user drag interrupts keyboard return and does not snap back',
      (tester) async {
    final logic = await mountChat(tester);
    logic.scrollController.jumpTo(900);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ChatListView)));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    expect(logic.focusNode.hasFocus, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
        logic.scrollController.offset -
            logic.scrollController.position.minScrollExtent,
        greaterThan(1));
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    logic.onDelete();
  });

  testWidgets('arrivals during keyboard return do not interrupt the animation',
      (tester) async {
    final logic = await mountChat(tester);
    logic.scrollController.jumpTo(900);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    receive(createMessage('during-keyboard-return', 100));
    await tester.pump(const Duration(milliseconds: 30));
    expect(logic.focusNode.hasFocus, isTrue);
    expect(
        logic.scrollController.offset -
            logic.scrollController.position.minScrollExtent,
        greaterThan(1));
    await tester.pumpAndSettle();
    expect(logic.scrollController.offset,
        closeTo(logic.scrollController.position.minScrollExtent, 1));
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.focusNode.hasFocus, isTrue);
    logic.onDelete();
  });
}
