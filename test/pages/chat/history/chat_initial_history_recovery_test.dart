import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';

import '../../../support/chat/chat_recovery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ChatLogic> openEmpty(
      WidgetTester tester, ChatRecoveryFixture fixture) async {
    Get.routing.args = {
      'conversationInfo':
          fixture.conversation(latest: recoveryMessage('known-latest', 1000)),
    };
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    logic.bindMessageRoute(fixture.route);
    await tester.idle();
    fixture.calls.single.complete([], isEnd: true);
    await tester.pump();
    expect(logic.messageList, isEmpty);
    return logic;
  }

  recoveryScenario(
      'empty first page recovers known latest without another push',
      (tester, fixture) async {
    final logic = await openEmpty(tester, fixture);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fixture.calls, hasLength(2));
    fixture.calls.last
        .complete([recoveryMessage('known-latest', 1000)], isEnd: true);
    await tester.pump();
    expect(logic.messageList.map((m) => m.clientMsgID), ['known-latest']);
    await tester.pump(const Duration(seconds: 10));
    expect(fixture.calls, hasLength(2));
  });

  recoveryScenario('empty history recovery has a finite retry budget',
      (tester, fixture) async {
    await openEmpty(tester, fixture);
    for (final delay in [
      const Duration(milliseconds: 100),
      const Duration(seconds: 1),
      const Duration(seconds: 3),
    ]) {
      final before = fixture.calls.length;
      await tester.pump(delay);
      expect(fixture.calls, hasLength(before + 1));
      fixture.calls.last.complete([], isEnd: true);
      await tester.pump();
    }
    await tester.pump(const Duration(minutes: 1));
    expect(fixture.calls, hasLength(4));
  });

  recoveryScenario('closing the page cancels cold history recovery',
      (tester, fixture) async {
    final logic = await openEmpty(tester, fixture);
    logic.onDelete();
    await tester.pump(const Duration(seconds: 10));
    expect(fixture.calls, hasLength(1));
  });
}
