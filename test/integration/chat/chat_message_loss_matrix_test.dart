import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import '../../support/chat/chat_recovery_fixture.dart';

List<Message> range(int first, int last) =>
    [for (var seq = first; seq <= last; seq++) recoveryMessage('m-$seq', seq)];
Future<void> resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.idle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final signal in ['wake', 'sync']) {
    for (final inFlight in [false, true]) {
      recoveryScenario(
          '$signal ${inFlight ? 'during' : 'after'} latest read coalesces and deduplicates live delivery',
          (tester, f) async {
        final logic = await f.open(tester);
        await resume(tester);
        final early = f.calls.last;
        f.im.recvNewMessage(recoveryMessage('m-1000', 1000));
        if (!inFlight) {
          early.complete([recoveryMessage('m-1000', 1000)], isEnd: false);
          await tester.pump();
        }
        for (var n = 0; n < 8; n++) {
          if (signal == 'wake') {
            f.im.historyRecoverySignals.add(null);
          } else {
            f.im.imSdkStatus(IMSdkStatus.syncEnded);
          }
        }
        await tester.idle();
        if (inFlight) {
          expect(f.calls, hasLength(2));
          early.complete([recoveryMessage('m-1000', 1000)], isEnd: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(f.calls, hasLength(3));
        expect(f.calls.last.arguments['startClientMsgID'], '');
        f.calls.last.complete(range(961, 1000), isEnd: false);
        await tester.pump();
        expect(logic.messageList.where((m) => m.seq == 1000), hasLength(1));
        for (var seq = 961; seq <= 1000; seq++) {
          expect(logic.messageList.where((m) => m.seq == seq), hasLength(1));
        }
        expect(logic.messageList.any((m) => m.seq == 2), isFalse);
      });
    }
  }

  for (final native in [false, true]) {
    recoveryScenario(
        '${native ? 'partial native' : 'network'} error preserves the installed window',
        (tester, f) async {
      final logic = await f.open(tester);
      await resume(tester);
      if (native) {
        f.calls.last.result.complete(jsonEncode(AdvancedMessage(
                messageList: range(961, 1000),
                isEnd: false,
                errCode: 10002,
                errMsg: 'native pull incomplete')
            .toJson()));
      } else {
        f.calls.last.result.completeError(PlatformException(code: 'offline'));
      }
      await tester.pump();
      expect(logic.messageList.map((m) => m.seq), [1]);
      expect(logic.historyError.value, isNotNull);
      await tester.pump(const Duration(seconds: 1));
      expect(f.calls.last.arguments['startClientMsgID'], '');
      f.calls.last.complete(range(961, 1000), isEnd: false);
      await tester.pump();
      expect(logic.messageList.last.seq, 1000);
      expect(logic.historyError.value, isNull);
    });
  }

  recoveryScenario(
      'deleted sequence holes never start unbounded forward recovery',
      (tester, f) async {
    final logic = await f.open(tester);
    await resume(tester);
    final page = [
      recoveryMessage('m-990', 990),
      recoveryMessage('m-1000', 1000)
    ];
    f.calls.last.complete(page, isEnd: false);
    await tester.pump();
    for (final seconds in [1, 3]) {
      await tester.pump(Duration(seconds: seconds));
      expect(f.calls.last.arguments['startClientMsgID'], '');
      f.calls.last.complete(page, isEnd: false);
      await tester.pump();
    }
    final reads = f.calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(f.calls, hasLength(reads));
    expect(logic.messageList.map((m) => m.seq), [990, 1000]);
  });

  for (final action in ['clear', 'close', 'account']) {
    recoveryScenario('queued latest recheck is cancelled by $action',
        (tester, f) async {
      final logic = await f.open(tester);
      await resume(tester);
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
      early.complete(range(961, 1000), isEnd: false);
      await tester.pump(const Duration(seconds: 35));
      expect(f.calls, hasLength(2));
      expect(logic.messageList.map((m) => m.seq),
          action == 'clear' ? <int>[] : [1]);
    });
  }
}
