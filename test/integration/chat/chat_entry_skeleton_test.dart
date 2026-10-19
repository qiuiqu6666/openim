import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/loading/chat_entry_loading_hint.dart';
import 'package:openim/pages/chat/messages/loading/chat_initial_window_transition.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';

import '../../support/chat/chat_recovery_fixture.dart';

void main() {
  recoveryScenario(
      'local messages paint without waiting for remote history or fade',
      (tester, fixture) async {
    final latest = recoveryMessage('local-real', 1);
    fixture.localSnapshot = [latest];
    Get.routing.args = {
      'conversationInfo': fixture.conversation(latest: latest)
    };
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            home: Scaffold(
                body: ChatMessageList(
                    logic: logic,
                    messageBuilder: (_, message) => SizedBox(
                        height: 48, child: Text(message.clientMsgID!)))))));
    await tester.pump();
    expect(fixture.calls.single.result.isCompleted, isFalse);
    expect(find.text('local-real'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing,
        reason: 'Initial validation is not manual history pagination');
    expect(fixture.calls, hasLength(1));
    expect(find.byType(ChatEntryLoadingHint), findsNothing);
    expect(
        tester
            .widget<Opacity>(find
                .descendant(
                    of: find.byType(ChatInitialWindowTransition),
                    matching: find.byType(Opacity))
                .first)
            .opacity,
        1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(ChatEntryLoadingHint), findsNothing);
    fixture.calls.single.complete([latest], isEnd: true);
    await tester.pumpAndSettle();
    expect(find.text('local-real'), findsOneWidget);
  });

  recoveryScenario(
      'real entry loads a partial first page only after manual scrolling',
      (tester, fixture) async {
    final latest = recoveryMessage('latest', 10);
    Get.routing.args = {
      'conversationInfo': fixture.conversation(latest: latest)
    };
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            home: Scaffold(
                body: ChatMessageList(
                    logic: logic,
                    messageBuilder: (_, message) => SizedBox(
                        height: 48, child: Text(message.clientMsgID!)))))));
    fixture.calls.single.complete([latest], isEnd: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(fixture.calls.length, 1);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
    await tester.pump();
    expect(fixture.calls.length, 2);
    fixture.calls.last.complete(
        [for (var i = 1; i < 10; i++) recoveryMessage('older-$i', i)],
        isEnd: true);
    await tester.pumpAndSettle();
    expect(logic.messageList.length, 10);
    expect(find.text('latest'), findsOneWidget);
    expect(find.text('older-1'), findsOneWidget);
    expect(fixture.calls.length, 2);
    expect(tester.takeException(), isNull);
  });

  recoveryScenario(
      'real entry reveals the list once; hidden rows cannot acknowledge reads',
      (tester, fixture) async {
    final latest = recoveryMessage('latest', 1);
    Get.routing.args = {
      'conversationInfo': fixture.conversation(latest: latest)
    };
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            home: Scaffold(
                body: ChatMessageList(
                    logic: logic,
                    messageBuilder: (_, message) => SizedBox(
                        height: 48, child: Text(message.clientMsgID!)))))));
    await tester.pump(const Duration(milliseconds: 80));
    int reads() => fixture.nativeCalls
        .where((call) => call.method == 'markConversationMessageAsRead')
        .length;
    expect(find.byType(ChatEntryLoadingHint), findsNothing);
    expect(reads(), 0);
    fixture.calls.single.complete([latest], isEnd: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ChatEntryLoadingHint), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byType(ChatEntryLoadingHint), findsNothing);
    expect(find.text('latest'), findsOneWidget);
    expect(reads(), 1);
    expect(tester.takeException(), isNull);
  });
}
