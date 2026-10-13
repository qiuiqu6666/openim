import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';

import '../../support/chat/chat_recovery_fixture.dart';

List<Message> _range(int from, int to) => [
      for (var seq = from; seq <= to; seq++) recoveryMessage('m-$seq', seq),
    ];

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.idle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final covered in [false, true]) {
    recoveryScenario(
        '${covered ? 'covered page' : 'background'} drains more than two pages with duplicate delivery',
        (tester, f) async {
      final logic = await f.open(tester);
      if (covered) {
        for (var seq = 2; seq <= 30; seq++) {
          f.im.recvNewMessage(recoveryMessage('m-$seq', seq));
        }
        await tester.pumpAndSettle();
        logic.scrollController.jumpTo(500);
        await tester.pump();
        f.cover(true);
        await tester.pump();
        f.cover(false);
        await tester.pump();
      } else {
        await _resume(tester);
      }
      final firstSeq = covered ? 31 : 2;
      final lastSeq = firstSeq + 92;
      expect(f.calls.last.arguments['startClientMsgID'],
          covered ? 'm-30' : 'initial');
      f.im.recvNewMessage(recoveryMessage('m-$lastSeq', lastSeq));
      f.calls.last.complete(_range(firstSeq, firstSeq + 39), isEnd: false);
      await tester.pump();
      expect(f.calls.last.arguments['startClientMsgID'], 'm-${firstSeq + 39}');
      f.im.recvOfflineMessage(
          recoveryMessage('m-${firstSeq + 15}', firstSeq + 15));
      f.calls.last.complete(
          _range(firstSeq + 40, firstSeq + 79).reversed.toList(),
          isEnd: false);
      await tester.pump();
      expect(f.calls.last.arguments['startClientMsgID'], 'm-${firstSeq + 79}');
      f.calls.last.complete(_range(firstSeq + 80, lastSeq));
      await tester.pump();
      final ids = logic.messageList.map((m) => m.clientMsgID).toList();
      for (var seq = firstSeq; seq <= lastSeq; seq++) {
        expect(ids.where((id) => id == 'm-$seq'), hasLength(1),
            reason: 'Every persisted message must occur exactly once: $seq');
      }
      expect(logic.messageList.last.seq, lastSeq);
    });
  }

  recoveryScenario(
      'sync completion and repeated wakes reread after stale snapshot',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    final stale = f.calls.last;
    f.im.imSdkStatus(IMSdkStatus.syncStart);
    f.im.imSdkStatus(IMSdkStatus.syncEnded);
    for (var i = 0; i < 8; i++) {
      f.im.historyRecoverySignals.add(null);
    }
    await tester.idle();
    expect(f.calls, hasLength(2));
    stale.complete([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(f.calls, hasLength(3));
    expect(f.calls.last.arguments['startClientMsgID'], 'initial');
    f.calls.last.complete(_range(2, 40));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq).toList(),
        [for (var seq = 1; seq <= 40; seq++) seq]);
  });

  recoveryScenario('middle page network failure preserves last committed page',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.complete(_range(2, 41), isEnd: false);
    await tester.pump();
    expect(f.calls.last.arguments['startClientMsgID'], 'm-41');
    f.calls.last.result.completeError(PlatformException(code: 'offline'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(f.calls.last.arguments['startClientMsgID'], 'm-41');
    f.calls.last.complete(_range(42, 81));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq).toList(),
        [for (var seq = 1; seq <= 81; seq++) seq]);
  });

  recoveryScenario('account change rejects an outstanding second recovery page',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.complete(_range(2, 41), isEnd: false);
    await tester.pump();
    final prior = logic.messageList.map((m) => m.clientMsgID).toList();
    OpenIM.iMManager.userID = 'other-account';
    f.calls.last.complete(_range(42, 81));
    f.im.recvNewMessage(recoveryMessage('wrong-account', 82));
    f.im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump(const Duration(seconds: 35));
    expect(logic.messageList.map((m) => m.clientMsgID), prior);
    expect(f.calls, hasLength(3));
  });

  recoveryScenario(
      'native partial error cannot publish rows or move the cursor',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.result.complete(jsonEncode(AdvancedMessage(
      messageList: _range(2, 20),
      isEnd: true,
      errCode: 10002,
      errMsg: 'native pull did not complete',
    ).toJson()));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq), [1]);
    await tester.pump(const Duration(seconds: 1));
    expect(f.calls.last.arguments['startClientMsgID'], 'initial');
    f.calls.last.complete(_range(2, 41));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq).toList(),
        [for (var seq = 1; seq <= 41; seq++) seq]);
  });

  recoveryScenario('empty nonterminal page retries without crossing its anchor',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.complete([], isEnd: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(f.calls.last.arguments['startClientMsgID'], 'initial');
    f.calls.last.complete(_range(2, 18));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq).toList(),
        [for (var seq = 1; seq <= 18; seq++) seq]);
  });

  for (final inFlight in [false, true]) {
    for (final signal in ['wake', 'sync']) {
      recoveryScenario(
          '$signal ${inFlight ? 'during' : 'after'} sparse read recovers late middle rows',
          (tester, f) async {
        final logic = await f.open(tester);
        await _resume(tester);
        f.im.recvNewMessage(recoveryMessage('m-4', 4));
        final early = f.calls.last;
        // The early local snapshot contains the live row before the missing
        // interval is persisted. Only a fresh recovery event can verify it.
        if (!inFlight) {
          early.complete([recoveryMessage('m-4', 4)]);
          await tester.pump();
        }
        for (var i = 0; i < 8; i++) {
          if (signal == 'sync') {
            f.im.imSdkStatus(IMSdkStatus.syncStart);
            f.im.imSdkStatus(IMSdkStatus.syncEnded);
          } else {
            f.im.historyRecoverySignals.add(null);
          }
        }
        await tester.idle();
        if (inFlight) {
          expect(f.calls, hasLength(2));
          early.complete([recoveryMessage('m-4', 4)]);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(f.calls, hasLength(3));
        expect(f.calls.last.arguments['startClientMsgID'], 'initial');
        f.calls.last.complete(_range(2, 4));
        await tester.pump();
        expect(logic.messageList.map((m) => m.seq).toList(), [1, 2, 3, 4]);
      });
    }
  }

  recoveryScenario('legal deleted sequence holes do not create endless retries',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.complete([recoveryMessage('m-4', 4)]);
    await tester.pump();
    for (final seconds in [1, 3]) {
      await tester.pump(Duration(seconds: seconds));
      expect(f.calls.last.arguments['startClientMsgID'], 'm-4');
      f.calls.last.complete([]);
      await tester.pump();
    }
    final before = f.calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(f.calls, hasLength(before));
    expect(logic.historyError.value, isNull);
    expect(logic.messageList.map((m) => m.seq).toList(), [1, 4]);
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    expect(f.calls.last.arguments['startClientMsgID'], 'initial');
    f.calls.last.complete([recoveryMessage('m-4', 4)]);
    await tester.pump();
    for (final seconds in [1, 3]) {
      await tester.pump(Duration(seconds: seconds));
      f.calls.last.complete([]);
      await tester.pump();
    }
    final verifiedCount = f.calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(f.calls, hasLength(verifiedCount));
    expect(logic.historyError.value, isNull);
  });

  recoveryScenario('another background retains an unverified sparse boundary',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.complete([recoveryMessage('m-4', 4)]);
    await tester.pump();
    await _resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], 'initial');
    f.calls.last.complete(_range(2, 4));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq).toList(), [1, 2, 3, 4]);
    await _resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], 'm-4');
  });

  recoveryScenario('early sparse wake cannot certify a gap before later sync',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.complete([recoveryMessage('m-4', 4)]);
    await tester.pump();
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    expect(f.calls.last.arguments['startClientMsgID'], 'initial');
    // Wake only establishes connectivity. Native persistence is still behind.
    f.calls.last.complete([recoveryMessage('m-4', 4)]);
    await tester.pump();
    await _resume(tester);
    f.calls.last.complete(
        f.calls.last.arguments['startClientMsgID'] == 'initial'
            ? [recoveryMessage('m-4', 4)]
            : []);
    await tester.pump();
    // Only now is the missing interval available. The second background must
    // not have certified the incomplete wake snapshot as a new safe boundary.
    f.im.imSdkStatus(IMSdkStatus.syncStart);
    f.im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    f.calls.last.complete(
        f.calls.last.arguments['startClientMsgID'] == 'initial'
            ? _range(2, 4)
            : []);
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq).toList(), [1, 2, 3, 4]);
  });

  recoveryScenario(
      'a completed recovery gives the next background a new boundary',
      (tester, f) async {
    final logic = await f.open(tester);
    await _resume(tester);
    f.calls.last.complete(_range(2, 4));
    await tester.pump();
    await _resume(tester);
    expect(f.calls.last.arguments['startClientMsgID'], 'm-4');
    f.calls.last.complete(_range(5, 6));
    await tester.pump();
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    expect(f.calls.last.arguments['startClientMsgID'], 'm-4');
    f.calls.last.complete(_range(5, 6));
    await tester.pump();
    expect(logic.messageList.map((m) => m.seq).toList(), [1, 2, 3, 4, 5, 6]);
  });

  for (final action in ['clear', 'close', 'account']) {
    recoveryScenario('queued checkpoint verification is cancelled by $action',
        (tester, f) async {
      final logic = await f.open(tester);
      await _resume(tester);
      final early = f.calls.last;
      f.im.historyRecoverySignals.add(null);
      await tester.idle();
      if (action == 'clear') {
        logic.clearAllMessage();
      } else if (action == 'close') {
        logic.onDelete();
      } else {
        OpenIM.iMManager.userID = 'another-account';
      }
      early.complete(_range(2, 4));
      await tester.pump();
      await tester.pump(const Duration(seconds: 35));
      expect(f.calls, hasLength(2));
      expect(logic.messageList.map((m) => m.seq).toList(),
          action == 'clear' ? <int>[] : [1]);
    });
  }
}
