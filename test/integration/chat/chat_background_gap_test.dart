import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';

import '../../support/chat/chat_recovery_fixture.dart';
import '../../support/chat/chat_entry_list.dart';

Future<ChatLogic> readingWithTwoUnseen(
    WidgetTester tester, ChatRecoveryFixture fixture) async {
  final logic = await fixture.open(tester);
  for (var seq = 2; seq <= 30; seq++) {
    fixture.im.recvNewMessage(recoveryMessage('m-$seq', seq));
  }
  await tester.pumpAndSettle();
  logic.scrollController.jumpTo(500);
  await tester.pump();
  fixture.im.recvNewMessage(recoveryMessage('m-31', 31));
  fixture.im.recvNewMessage(recoveryMessage('m-32', 32));
  await tester.pump();
  expect(logic.newMessages.unseenCount.value, 2);
  return logic;
}

Future<void> resume(WidgetTester tester) async {
  WidgetsBinding.instance
      .handleAppLifecycleStateChanged(AppLifecycleState.paused);
  WidgetsBinding.instance
      .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.idle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  recoveryScenario('long outage retains checkpoint beyond initial retries',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    await resume(tester);
    for (final seconds in [1, 3, 30]) {
      expect(f.calls.last.arguments['startClientMsgID'], 'm-32');
      f.calls.last.result.completeError(PlatformException(code: 'offline'));
      await tester.pump();
      await tester.pump(Duration(seconds: seconds));
    }
    // No new SDK callback or user gesture is required when the network heals.
    expect(f.calls.last.arguments['startClientMsgID'], 'm-32');
    f.calls.last.complete(List.generate(100,
        (i) => recoveryMessage('m-${i + 33}', i + 33)));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 102);
    expect(logic.messageList.where((m) => m.clientMsgID == 'm-33'), hasLength(1));
    expect(logic.messageList.where((m) => m.clientMsgID == 'm-132'), hasLength(1));
  });

  recoveryScenario('bottom reader recovers a gap even when newest live arrives',
      (tester, f) async {
    final logic = await f.open(tester);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    await resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], 'initial');
    f.im.recvNewMessage(recoveryMessage('m-82', 82));
    f.calls.last.complete(
        List.generate(40, (i) => recoveryMessage('m-${i + 2}', i + 2)),
        isEnd: false);
    await tester.pump();
    expect(f.calls.last.arguments['startClientMsgID'], 'm-41');
    f.calls.last.complete(
        List.generate(41, (i) => recoveryMessage('m-${i + 42}', i + 42)));
    await tester.pump();
    final ids = logic.messageList.map((m) => m.clientMsgID).toList();
    expect(ids, hasLength(82));
    for (var seq = 2; seq <= 82; seq++) {
      expect(ids.where((id) => id == 'm-$seq'), hasLength(1));
    }
    expect(logic.messageList.last.clientMsgID, 'm-82');
  });

  recoveryScenario(
      'two unseen plus background backlog plus live stays complete',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    await resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], 'm-32');
    f.calls.last.complete(
        List.generate(40, (i) => recoveryMessage('m-${i + 33}', i + 33)),
        isEnd: false);
    await tester.pump();
    expect(f.calls.last.arguments['startClientMsgID'], 'm-72');
    // The latest live callback must not move the missing-message checkpoint.
    f.im.recvNewMessage(recoveryMessage('m-133', 133));
    await tester.pump();
    f.calls.last.complete(
        List.generate(40, (i) => recoveryMessage('m-${i + 73}', i + 73)),
        isEnd: false);
    await tester.pump();
    expect(f.calls.last.arguments['startClientMsgID'], 'm-112');
    f.calls.last.complete(
        List.generate(21, (i) => recoveryMessage('m-${i + 113}', i + 113)));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 103);
    final ids = logic.messageList.map((m) => m.clientMsgID).toList();
    for (var seq = 31; seq <= 133; seq++) {
      expect(ids.where((id) => id == 'm-$seq'), hasLength(1));
    }
    expect(logic.newMessages.awayFromLatest.value, isTrue);
  });

  recoveryScenario('recovery rows contribute to existing unseen count',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    await resume(tester);
    f.calls.last.complete(
        List.generate(8, (i) => recoveryMessage('m-${i + 33}', i + 33)));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 10);
    f.im.recvNewMessage(recoveryMessage('m-41', 41));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 11);
  });

  recoveryScenario(
      'historical window catches arrivals without jumping the reader',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    // Use the production scrolling widget and cross the automatic window cap.
    await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
    await tester.pump();
    logic.scrollController.jumpTo(500);
    await tester.pump();
    for (var seq = 33; seq <= 602; seq++) {
      f.im.recvNewMessage(recoveryMessage('m-$seq', seq));
    }
    await tester.pump();
    expect(logic.viewingHistory.value, isTrue);
    final oldIDs = logic.messageList.map((m) => m.clientMsgID).toList();
    final count = logic.newMessages.unseenCount.value;
    await resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], 'm-602');
    f.calls.last.complete(
        List.generate(40, (i) => recoveryMessage('m-${i + 603}', i + 603)),
        isEnd: false);
    await tester.pump();
    f.calls.last.complete(
        List.generate(40, (i) => recoveryMessage('m-${i + 643}', i + 643)),
        isEnd: false);
    await tester.pump();
    f.calls.last.complete(
        List.generate(40, (i) => recoveryMessage('m-${i + 683}', i + 683)));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, count + 120);
    expect(logic.messageList.map((m) => m.clientMsgID), oldIDs);
    expect(logic.scrollingCacheMessageList, hasLength(100));
    expect(logic.historyNewerHasMore.value, isTrue);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
  });

  recoveryScenario('partial recovery failure retries the unfinished page only',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    await resume(tester);
    f.calls.last.complete(
        List.generate(40, (i) => recoveryMessage('m-${i + 33}', i + 33)),
        isEnd: false);
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 42);
    f.calls.last.result.completeError(PlatformException(code: 'offline'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(f.calls.last.arguments['startClientMsgID'], 'm-72');
    f.calls.last.complete([recoveryMessage('m-73', 73)]);
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 43);
  });

  recoveryScenario(
      'empty early read does not lose delayed background persistence',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    await resume(tester);
    f.calls.last.complete([]);
    await tester.pump();
    f.im.recvNewMessage(recoveryMessage('m-41', 41));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(f.calls.last.arguments['startClientMsgID'], 'm-32');
    f.calls.last.complete(
        List.generate(9, (i) => recoveryMessage('m-${i + 33}', i + 33)));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 11);
  });

  recoveryScenario(
      'sync and wake during recovery coalesce without skipping gaps',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    await resume(tester);
    final count = f.calls.length;
    f.im.historyRecoverySignals.add(null);
    f.im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    expect(f.calls, hasLength(count));
    f.calls.last.complete([recoveryMessage('m-33', 33)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(f.calls, hasLength(count + 1));
    expect(f.calls.last.arguments['startClientMsgID'], 'm-33');
    f.calls.last.complete([recoveryMessage('m-34', 34)]);
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 4);
  });

  for (final action in ['clear', 'account', 'close']) {
    recoveryScenario('late recovery is ignored after $action',
        (tester, f) async {
      final logic = await readingWithTwoUnseen(tester, f);
      await resume(tester);
      final pending = f.calls.last;
      if (action == 'clear') {
        logic.clearAllMessage();
      } else if (action == 'account') {
        OpenIM.iMManager.userID = 'other';
      } else {
        logic.onDelete();
      }
      pending.complete([recoveryMessage('late', 33)]);
      await tester.pump();
      expect(logic.messageList.any((m) => m.clientMsgID == 'late'), isFalse);
      expect(
          logic.scrollingCacheMessageList.any((m) => m.clientMsgID == 'late'),
          isFalse);
    });
  }

  recoveryScenario(
      'second background never moves a still-missing checkpoint past live traffic',
      (tester, f) async {
    final logic = await readingWithTwoUnseen(tester, f);
    await resume(tester);
    f.calls.last.complete([]);
    await tester.pump();
    f.im.recvNewMessage(recoveryMessage('m-41', 41));
    await tester.pump();
    await resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], 'm-32');
    f.calls.last.complete(
        List.generate(9, (i) => recoveryMessage('m-${i + 33}', i + 33)));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 11);
  });
}
