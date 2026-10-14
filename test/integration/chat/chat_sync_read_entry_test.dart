import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';

import '../../support/chat/chat_recovery_fixture.dart';

Widget _productionList(ChatLogic logic) => ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
        home: Scaffold(
            body: ChatMessageList(
                logic: logic,
                messageBuilder: (_, message) =>
                    SizedBox(height: 48, child: Text(message.clientMsgID!))))));

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
    await tester.pumpAndSettle();
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
}
