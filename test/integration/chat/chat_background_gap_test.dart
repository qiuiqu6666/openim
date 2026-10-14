import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import '../../support/chat/chat_recovery_fixture.dart';

Future<void> resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.idle();
}

List<Message> tail(int max) => [
      for (var seq = max - 39; seq <= max; seq++) recoveryMessage('m-$seq', seq)
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  recoveryScenario(
      'one hundred million history rows only refresh the latest page',
      (tester, f) async {
    final logic = await f.open(tester);
    logic.inputCtrl.text = 'keep draft';
    await resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], '');
    expect(f.calls.last.arguments['count'], lessThanOrEqualTo(100));
    f.im.recvNewMessage(recoveryMessage('m-100000001', 100000001));
    f.calls.last.complete(tail(100000000), isEnd: false);
    await tester.pump();
    expect(logic.messageList.last.seq, 100000001);
    expect(logic.messageList.any((m) => m.seq == 1), isFalse);
    expect(logic.inputCtrl.text, 'keep draft');
    expect(f.calls, hasLength(2), reason: 'No immediate forward pagination');
    for (final seconds in [1, 3]) {
      await tester.pump(Duration(seconds: seconds));
      expect(f.calls.last.arguments['startClientMsgID'], '');
      f.calls.last.complete(tail(100000001), isEnd: false);
      await tester.pump();
    }
    final reads = f.calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(f.calls, hasLength(reads));
    expect(
        f.nativeCalls
            .where((c) => c.method == 'getAdvancedHistoryMessageListReverse'),
        isEmpty);
    expect(logic.messageList.length, lessThanOrEqualTo(100));
  });

  recoveryScenario(
      'only an explicit older-page gesture downloads older history',
      (tester, f) async {
    final logic = await f.open(tester);
    await resume(tester);
    f.calls.last.complete(tail(1000), isEnd: false);
    await tester.pump();
    final reads = f.calls.length;
    final pending = logic.onScrollToBottomLoad();
    await tester.idle();
    expect(f.calls, hasLength(reads + 1));
    expect(f.calls.last.arguments['startClientMsgID'], 'm-961');
    f.calls.last.complete(tail(960), isEnd: false);
    await tester.pump();
    await pending;
    expect(logic.messageList.first.seq, 921);
    expect(logic.messageList.last.seq, 1000);
  });

  recoveryScenario(
      'reader keeps a historical window across resume and live traffic',
      (tester, f) async {
    final logic = await f.open(tester);
    final seek = logic.jumpToDateMessage(recoveryMessage('m-50', 50));
    await tester.idle();
    f.calls[f.calls.length - 2]
        .complete([recoveryMessage('m-49', 49)], isEnd: false);
    f.calls.last.complete([recoveryMessage('m-51', 51)], isEnd: false);
    await tester.pump();
    await tester.pump();
    await seek;
    final before = logic.messageList.map((m) => m.seq).toList();
    final reads = f.calls.length;
    await resume(tester);
    f.im.recvNewMessage(recoveryMessage('latest', 100000000));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq), before);
    expect(logic.scrollingCacheMessageList.last.seq, 100000000);
    expect(f.calls, hasLength(reads));
    expect(logic.historyNewerHasMore.value, isTrue);
  });

  recoveryScenario('reconnection renews a finite latest-window budget',
      (tester, f) async {
    final logic = await f.open(tester);
    await resume(tester);
    for (final seconds in [1, 3]) {
      f.calls.last.complete([], isEnd: false);
      await tester.pump();
      await tester.pump(Duration(seconds: seconds));
    }
    f.calls.last.complete([], isEnd: false);
    await tester.pump();
    final reads = f.calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(f.calls, hasLength(reads));
    f.im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.idle();
    expect(f.calls, hasLength(reads + 1));
    expect(f.calls.last.arguments['startClientMsgID'], '');
    f.calls.last.complete(tail(1000), isEnd: false);
    await tester.pump();
    expect(logic.messageList.last.seq, 1000);
  });

  for (final action in ['clear', 'account', 'close']) {
    recoveryScenario('late latest-window response is ignored after $action',
        (tester, f) async {
      final logic = await f.open(tester);
      await resume(tester);
      final pending = f.calls.last;
      if (action == 'clear') {
        logic.clearAllMessage();
      } else if (action == 'account') {
        OpenIM.iMManager.userID = 'other';
      } else {
        logic.onDelete();
      }
      pending.complete(tail(1000), isEnd: false);
      await tester.pump(const Duration(seconds: 35));
      expect(logic.messageList.any((m) => m.seq == 1000), isFalse);
      expect(f.calls, hasLength(2));
    });
  }
}
