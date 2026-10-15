import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import 'package:openim_common/src/widgets/chat/chat_list_viewport.dart';

import '../../support/chat/chat_recovery_fixture.dart';

Widget _productionList(ChatLogic logic) => ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
        home: Scaffold(
            body: ChatMessageList(
                logic: logic,
                messageBuilder: (_, message) =>
                    SizedBox(height: 48, child: Text(message.clientMsgID!))))));

// Keep rows mounted without subscribing to loading or SDK status. A gate-only
// transition must request a fresh painted observation even without a rebuild.
Widget _stationaryList(ChatLogic logic) => MaterialApp(
    home: SizedBox(
        height: 240,
        child: ChatListViewport(
          positionController: logic.messagePositionController,
          controller: logic.scrollController,
          messageIDs: const ['initial'],
          itemCount: 1,
          padding: EdgeInsets.zero,
          itemBuilder: (_, __) => const SizedBox(height: 48),
          onViewportChanged: logic.onChatViewportChanged,
        )));

void main() {
  int reads(ChatRecoveryFixture fixture) => fixture.nativeCalls
      .where((call) => call.method == 'markConversationMessageAsRead')
      .length;

  recoveryScenario(
      'entering after global sync failure reads the painted local latest',
      (tester, fixture) async {
    fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
    final logic = await fixture.open(tester);
    logic.conversationInfo =
        fixture.conversation(latest: logic.messageList.last);
    await tester.pumpWidget(_productionList(logic));
    await tester.pumpAndSettle();
    expect(logic.historyError.value, isNull);
    expect(reads(fixture), 1);
  });

  recoveryScenario('sync failure remeasures an unchanged production viewport',
      (tester, fixture) async {
    fixture.im.imSdkStatus(IMSdkStatus.syncStart);
    final logic = await fixture.open(tester);
    logic.conversationInfo =
        fixture.conversation(latest: logic.messageList.last);
    await tester.pumpWidget(_productionList(logic));
    // The loading skeleton intentionally pulses until this sync barrier settles.
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads(fixture), 0);
    fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
    await tester.pumpAndSettle();
    expect(reads(fixture), 1);
  });

  recoveryScenario('sync failure does not read an announced but missing latest',
      (tester, fixture) async {
    fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
    final logic = await fixture.open(tester);
    logic.conversationInfo =
        fixture.conversation(latest: recoveryMessage('missing', 2));
    await tester.pumpWidget(_productionList(logic));
    await tester.pumpAndSettle();
    expect(reads(fixture), 0);
  });

  recoveryScenario('repeated sync status preserves a painted read retry',
      (tester, fixture) async {
    fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
    final logic =
        await fixture.open(tester, receiptNow: tester.binding.clock.now);
    logic.conversationInfo =
        fixture.conversation(latest: logic.messageList.last);
    var failRead = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ChatRecoveryFixture.channel, (call) async {
      fixture.nativeCalls.add(call);
      if (call.method == 'markConversationMessageAsRead' && failRead) {
        throw PlatformException(code: 'NETWORK_FAILURE');
      }
      return null;
    });
    await tester.pumpWidget(_productionList(logic));
    await tester.pumpAndSettle();
    expect(reads(fixture), 1);

    failRead = false;
    fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
    await tester.pump();
    fixture.announce('initial', 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(reads(fixture), 2,
        reason: 'A duplicate status must not lose the still-painted viewport');
  });
  recoveryScenario('settled history remeasures an unsequenced latest',
      (tester, fixture) async {
    final logic = await fixture.open(tester);
    logic.conversationInfo =
        fixture.conversation(latest: logic.messageList.last);
    logic.messageList.last.seq = 0;
    logic.historyLoading.value = true;
    await tester.pumpWidget(_stationaryList(logic));
    await tester.pumpAndSettle();
    expect(reads(fixture), 0);

    logic.historyLoading.value = false;
    await tester.pumpAndSettle();
    expect(reads(fixture), 1);
  });

  recoveryScenario('settled history cannot read a covered chat',
      (tester, fixture) async {
    final logic = await fixture.open(tester);
    logic.conversationInfo =
        fixture.conversation(latest: logic.messageList.last);
    logic.messageList.last.seq = 0;
    logic.historyLoading.value = true;
    await tester.pumpWidget(_stationaryList(logic));
    await tester.pumpAndSettle();
    fixture.cover(true);
    logic.historyLoading.value = false;
    await tester.pumpAndSettle();
    expect(reads(fixture), 0);
  });

  recoveryScenario('reconnection retries a failed read without scrolling',
      (tester, fixture) async {
    fixture.im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    final logic =
        await fixture.open(tester, receiptNow: tester.binding.clock.now);
    logic.conversationInfo =
        fixture.conversation(latest: logic.messageList.last);
    var failRead = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ChatRecoveryFixture.channel, (call) async {
      fixture.nativeCalls.add(call);
      if (call.method == 'markConversationMessageAsRead' && failRead) {
        throw PlatformException(code: 'NETWORK_FAILURE');
      }
      return null;
    });
    await tester.pumpWidget(_stationaryList(logic));
    await tester.pumpAndSettle();
    expect(reads(fixture), 1);
    // Drain the existing 250ms viewport coalescing window first.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    final failedAttempts = reads(fixture);
    await tester.pump(const Duration(seconds: 2));
    expect(reads(fixture), failedAttempts,
        reason: 'No endless retry while offline');

    failRead = false;
    fixture.im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.pumpAndSettle();
    expect(reads(fixture), failedAttempts + 1);
    fixture.im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.pumpAndSettle();
    expect(reads(fixture), failedAttempts + 1,
        reason: 'A successful target remains coalesced');
  });
}
