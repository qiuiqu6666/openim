import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';

import '../../support/chat/chat_recovery_fixture.dart';

class _ChatRoute extends StatefulWidget {
  const _ChatRoute(this.logic);
  final ChatLogic logic;
  @override
  State<_ChatRoute> createState() => _ChatRouteState();
}

class _ChatRouteState extends State<_ChatRoute> {
  @override
  Widget build(BuildContext context) => Scaffold(
      body: ChatMessageList(
          logic: widget.logic,
          messageBuilder: (_, message) =>
              SizedBox(height: 48, child: Text(message.clientMsgID!))));
  @override
  void dispose() {
    widget.logic.onDelete();
    super.dispose();
  }
}

void main() {
  int reads(ChatRecoveryFixture fixture) => fixture.nativeCalls
      .where((call) => call.method == 'markConversationMessageAsRead')
      .length;

  for (final group in [false, true]) {
    recoveryScenario(
        'painted latest reads before slow history and quick pop group=$group',
        (tester, fixture) async {
      fixture.im.imSdkStatus(IMSdkStatus.syncFailed);
      final preview = recoveryMessage('preview', 713);
      final info = fixture.conversation(latest: preview);
      if (group) {
        info.conversationID = 'sg_group';
        info.groupID = 'group';
        info.userID = null;
        info.conversationType = ConversationType.superGroup;
        preview.groupID = 'group';
        preview.sessionType = ConversationType.superGroup;
      }
      Get.routing.args = {'conversationInfo': info};
      final logic =
          fixture.logic = ChatLogic(receiptNow: tester.binding.clock.now);
      logic.onInit();
      await tester.idle();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) =>
              MaterialApp(navigatorKey: navigator, home: const Scaffold())));
      navigator.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => _ChatRoute(logic)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(logic.historyLoading.value, isTrue);
      expect(reads(fixture), 1,
          reason: 'Painted persisted latest must not wait for older history');

      // Deliver the successful SDK unread snapshot before leaving.
      logic.conversationInfo.unreadCount = 0;
      navigator.currentState!.pop();
      await tester.pump();
      // Finish history while the real route is reversing its exit transition.
      fixture.calls.first.complete([preview], isEnd: false);
      await tester.pump();
      final attemptsAfterPop = reads(fixture);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(logic.isClosed, isTrue);
      expect(reads(fixture), attemptsAfterPop,
          reason: 'No deferred full read after route disposal');
    });
  }

  recoveryScenario('loading a missing latest never clears a painted older row',
      (tester, fixture) async {
    final logic = await fixture.open(tester);
    logic.historyLoading.value = true;
    logic.conversationInfo =
        fixture.conversation(latest: recoveryMessage('missing', 2));
    logic.onChatViewportChanged(['initial'], 0);
    await tester.pump();
    logic.onDelete();
    expect(reads(fixture), 0);
  });

  recoveryScenario('unpainted persisted preview does not clear on exit',
      (tester, fixture) async {
    Get.routing.args = {
      'conversationInfo':
          fixture.conversation(latest: recoveryMessage('preview', 713))
    };
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    await tester.idle();
    logic.onDelete();
    expect(reads(fixture), 0);
  });
}
