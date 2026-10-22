import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import '../../support/chat/chat_recovery_fixture.dart';

void main() {
  recoveryScenario(
      'mounted route submits entry cutoff before any history paints',
      (tester, fixture) async {
    final preview = recoveryMessage('preview', 100);
    final info = fixture.conversation(latest: preview)
      ..conversationID = 'si_peer_self';
    Get.routing.args = {'conversationInfo': info};
    final targets = <int>[];
    final subscription = fixture.im.conversationEntryReadSubject
        .listen((t) => targets.add(t.hasReadSeq));
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    logic.bindMessageRoute(fixture.route);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(logic.messageList, isEmpty);
    expect(targets, [100]);
    preview.seq = 101;
    logic.bindMessageRoute(fixture.route);
    tester.binding.scheduleFrame();
    await tester.pump();
    logic.onDelete();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(targets, [100]);
    subscription.cancel();
  });

  recoveryScenario('history entry does not issue entry cutoff',
      (tester, fixture) async {
    final preview = recoveryMessage('preview', 100);
    Get.routing.args = {
      'conversationInfo': fixture.conversation(latest: preview)
        ..conversationID = 'si_peer_self',
      'searchMessage': recoveryMessage('old', 10)
    };
    final targets = <int>[];
    final subscription = fixture.im.conversationEntryReadSubject
        .listen((t) => targets.add(t.hasReadSeq));
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    logic.bindMessageRoute(fixture.route);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(targets, isEmpty);
    subscription.cancel();
  });

  recoveryScenario(
      'covered/background/disposed route cannot initiate entry read',
      (tester, fixture) async {
    Get.routing.args = {
      'conversationInfo':
          fixture.conversation(latest: recoveryMessage('preview', 100))
            ..conversationID = 'si_peer_self'
    };
    final targets = <int>[];
    final subscription = fixture.im.conversationEntryReadSubject
        .listen((t) => targets.add(t.hasReadSeq));
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    fixture.route.current = false;
    logic.bindMessageRoute(fixture.route);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(targets, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fixture.route.current = true;
    logic.bindMessageRoute(fixture.route);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(targets, isEmpty);
    logic.onDelete();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(targets, isEmpty);
    subscription.cancel();
  });
}
