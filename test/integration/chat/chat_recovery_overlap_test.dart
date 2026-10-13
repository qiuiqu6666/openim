import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';

import '../../support/chat/chat_recovery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  recoveryScenario('sync in progress does not suspend latest message recovery',
      (tester, f) async {
    final logic = await f.open(tester);
    f.im.imSdkStatus(IMSdkStatus.syncStart);
    await tester.pump();
    f.announce('during-sync', 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.calls, hasLength(2));
    f.calls.last.complete(
        [recoveryMessage('initial', 1), recoveryMessage('during-sync', 2)]);
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'during-sync');
    expect(logic.syncStatus.value, IMSdkStatus.syncStart);
  });

  recoveryScenario('summary before persistence rechecks the same missing ID',
      (tester, f) async {
    final logic = await f.open(tester);
    f.announce('late-commit', 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.calls, hasLength(2));
    f.calls.last.complete([recoveryMessage('initial', 1)]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(f.calls, hasLength(3));
    f.calls.last.complete(
        [recoveryMessage('initial', 1), recoveryMessage('late-commit', 2)]);
    await tester.pump();
    await tester.pump();
    expect(find.text('late-commit'), findsOneWidget);
    expect(logic.messageList.last.clientMsgID, 'late-commit');
  });

  recoveryScenario(
      'network wake restarts recovery after the retry budget expired',
      (tester, f) async {
    final logic = await f.open(tester);
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    for (final delay in [1, 3, 5]) {
      f.calls.last.result.completeError(PlatformException(code: 'offline'));
      await tester.pump();
      await tester.pump(Duration(seconds: delay));
    }
    expect(f.calls, hasLength(4));
    expect(logic.historyError.value, isNotNull);
    f.im.historyRecoverySignals.add(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(f.calls, hasLength(5));
    f.calls.last.complete([recoveryMessage('after-network', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'after-network');
  });

  recoveryScenario(
      'late pre-cover query cannot consume covered message recovery',
      (tester, f) async {
    final logic = await f.open(tester);
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    expect(f.calls, hasLength(2));
    f.cover(true);
    f.im.recvOfflineMessage(recoveryMessage('while-covered', 2));
    expect(logic.scrollingCacheMessageList, hasLength(1));
    f.calls.last.complete([recoveryMessage('initial', 1)]);
    await tester.pump();
    f.cover(false);
    await tester.pump();
    await tester.pump();
    expect(f.calls, hasLength(3));
    f.calls.last.complete(
        [recoveryMessage('initial', 1), recoveryMessage('while-covered', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'while-covered');
  });

  recoveryScenario('wake during an already queued refresh is not swallowed',
      (tester, f) async {
    final logic = await f.open(tester);
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    f.calls.last.complete([recoveryMessage('initial', 1)]);
    await tester.pump();
    expect(f.calls, hasLength(3));
    // Persistence finishes only after the queued query captured its snapshot.
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    f.calls.last.complete([recoveryMessage('initial', 1)]);
    await tester.pump();
    expect(f.calls, hasLength(4));
    f.calls.last.complete([recoveryMessage('persisted-after-queued-read', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'persisted-after-queued-read');
  });

  recoveryScenario('paused retry resumes after a covered failed refresh',
      (tester, f) async {
    final logic = await f.open(tester);
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    f.calls.last.result.completeError(PlatformException(code: 'offline'));
    await tester.pump();
    f.cover(true);
    await tester.pump(const Duration(seconds: 2));
    expect(f.calls, hasLength(2));
    expect(logic.historyError.value, isNotNull);
    f.cover(false);
    expect(logic.messageRoute!.isCurrent, isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(f.calls, hasLength(3));
    f.calls.last.complete([recoveryMessage('returned', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'returned');
  });

  recoveryScenario(
      'a summary received under a covering page recovers on return',
      (tester, f) async {
    final logic = await f.open(tester);
    f.cover(true);
    f.announce('summary-under-cover', 2);
    await tester.pump(const Duration(seconds: 1));
    expect(f.calls, hasLength(1));
    f.cover(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.calls, hasLength(2));
    f.calls.last.complete([recoveryMessage('summary-under-cover', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'summary-under-cover');
  });

  recoveryScenario('resume and sync preserve the target of a failed date seek',
      (tester, f) async {
    final logic = await f.open(tester);
    final target = recoveryMessage('date-target', -10);
    final seek = logic.jumpToDateMessage(target);
    await tester.idle();
    f.calls[1].result.completeError(PlatformException(code: 'offline'));
    f.calls[2].complete([]);
    await tester.pump();
    expect(await seek, isFalse);
    expect(logic.historyError.value, isNotNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    f.im.imSdkStatus(IMSdkStatus.syncStart);
    f.announce('latest-during-seek', 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(f.calls, hasLength(3));
    f.im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(f.calls, hasLength(5));
    for (final call in f.calls.skip(3)) {
      expect(call.arguments['startClientMsgID'], 'date-target');
    }
    f.calls[3].complete([recoveryMessage('older', -11)], isEnd: false);
    f.calls[4].complete([recoveryMessage('newer', -9)], isEnd: false);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(logic.viewingHistory.value, isTrue);
    expect(logic.historyError.value, isNull);
    expect(logic.messageList.map((m) => m.clientMsgID),
        ['older', 'date-target', 'newer']);
    expect(f.calls, hasLength(5));
  });

  recoveryScenario('repeated foreground switches keep only bounded reads',
      (tester, f) async {
    final logic = await f.open(tester);
    for (var i = 0; i < 20; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      f.im.historyRecoverySignals.add(null);
    }
    await tester.idle();
    expect(f.calls, hasLength(2));
    f.im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    f.calls.last.complete([recoveryMessage('initial', 1)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(f.calls, hasLength(3));
    f.calls.last.complete([recoveryMessage('latest', 10)]);
    await tester.pump();
    for (final delay in [1, 3]) {
      await tester.pump(Duration(seconds: delay));
      f.calls.last.complete([]);
      await tester.pump();
    }
    final settledCount = f.calls.length;
    await tester.pump(const Duration(seconds: 10));
    expect(f.calls, hasLength(settledCount));
    expect(settledCount, lessThanOrEqualTo(5));
    expect(logic.messageList.last.clientMsgID, 'latest');
  });

  recoveryScenario(
      'clear then a new summary can recover before an old read returns',
      (tester, f) async {
    final logic = await f.open(tester);
    f.announce('before-clear', 2);
    await tester.pump(const Duration(milliseconds: 100));
    final stale = f.calls.last;
    logic.clearAllMessage();
    f.announce('after-clear', 3);
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.calls, hasLength(3));
    f.calls.last.complete([recoveryMessage('after-clear', 3)]);
    await tester.pump();
    stale.complete([recoveryMessage('before-clear', 2)]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(logic.messageList.map((m) => m.clientMsgID), ['after-clear']);
    expect(f.calls, hasLength(3));
  });

  recoveryScenario('sync finish renews retries exhausted before the sync',
      (tester, f) async {
    final logic = await f.open(tester);
    f.im.historyRecoverySignals.add(null);
    await tester.idle();
    for (final delay in [1, 3, 5]) {
      f.calls.last.result.completeError(PlatformException(code: 'offline'));
      await tester.pump();
      await tester.pump(Duration(seconds: delay));
    }
    f.im.imSdkStatus(IMSdkStatus.syncStart);
    await tester.pump();
    f.im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(f.calls, hasLength(5));
    f.calls.last.complete([recoveryMessage('synced-after-errors', 4)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'synced-after-errors');
  });

  recoveryScenario('a permanently unavailable summary has a finite read budget',
      (tester, f) async {
    await f.open(tester);
    f.announce('unavailable', 2);
    for (final wait in [100, 1000, 3000]) {
      await tester.pump(Duration(milliseconds: wait));
      f.calls.last.complete([recoveryMessage('initial', 1)]);
      await tester.pump();
    }
    expect(f.calls, hasLength(4));
    for (var i = 0; i < 5; i++) {
      f.announce('unavailable', 2);
      await tester.pump(const Duration(minutes: 1));
    }
    expect(f.calls, hasLength(4));
  });

  recoveryScenario(
      'late old-account read and live callbacks cannot alter the page',
      (tester, f) async {
    final logic = await f.open(tester);
    f.announce('old-account', 2);
    await tester.pump(const Duration(milliseconds: 100));
    final pending = f.calls.last;
    logic.onDelete();
    f.im.recvOfflineMessage(recoveryMessage('late-offline', 3));
    pending.complete([recoveryMessage('old-account', 2)]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(logic.messageList.map((m) => m.clientMsgID), ['initial']);
    expect(f.calls, hasLength(2));
  });
}
