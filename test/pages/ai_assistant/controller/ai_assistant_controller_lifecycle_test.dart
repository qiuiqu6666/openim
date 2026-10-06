import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/controller/ai_assistant_controller.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_api.dart';
import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_assistant_controller_test_fakes.dart';

void _send(AiAssistantController controller, FakeAsync clock, String text) {
  bool? accepted;
  controller.send(text).then((value) => accepted = value);
  clock.flushMicrotasks();
  expect(accepted, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  test('default UI controller never opens HTTP and disabled sends keep drafts',
      () async {
    var httpClients = 0;
    await HttpOverrides.runZoned(() async {
      final defaultController = AiAssistantController(
        sessionProvider: () => (userID: 'owner', token: 'owner-token'),
      );
      try {
        expect(defaultController.serviceEnabled, isFalse);
        await defaultController.initialize();
        await defaultController.loadHistory();
        expect(await defaultController.send('A question'), isFalse);
        expect(await defaultController.clearHistory(), isTrue);
        expect(defaultController.historyLoaded, isTrue);
        expect(defaultController.messages, isEmpty);
        expect(httpClients, 0);
      } finally {
        defaultController.dispose();
      }
    }, createHttpClient: (_) {
      httpClients++;
      throw StateError('HTTP is forbidden in this UI-only test');
    });

    final harness = AiControllerTestHarness(serviceEnabled: false);
    addTearDown(harness.dispose);
    const card = AiAssistantCardRef(
        kind: AiAssistantCardKind.friend, id: 'friend', name: 'Friend');
    expect(harness.controller.addCard(card), isTrue);
    harness.controller.selectTool('summarize');
    final draft = harness.controller.drafts.single;
    await harness.controller.initialize();
    expect(
        await harness.controller.send('Keep the summary requirement'), isFalse);
    expect(await harness.controller.clearHistory(), isTrue);
    expect(harness.controller.drafts.single, same(draft));
    expect(harness.controller.drafts.single.card, same(card));
    expect(harness.controller.selectedTool, 'summarize');
    expect(harness.controller.messages, isEmpty);
    expect(harness.controller.reply, isNull);
    expect(harness.api.historyTokens, isEmpty);
    expect(harness.api.turns, isEmpty);
    expect(harness.api.uploadCalls, 0);
    expect(harness.api.downloadCalls, 0);
    expect(harness.api.deleteCalls, 0);
  });

  test('late history cannot replace a send that superseded its request',
      () async {
    final harness = AiControllerTestHarness();
    addTearDown(harness.dispose);
    final pending = Completer<AiAssistantHistoryPage>();
    harness.api.onHistory = () => pending.future;
    var notifications = 0;
    harness.controller.addListener(() => notifications++);
    final loading = harness.controller.loadHistory();
    expect(harness.controller.historyLoading, isTrue);
    expect(harness.api.historyTokens, hasLength(1));
    expect(await harness.controller.send('Send before history'), isTrue);
    final turn = harness.controller.reply;
    final beforeLateHistory = notifications;
    expect(harness.api.historyTokens.single!.isCancelled, isTrue);

    pending.complete(aiControllerHistory('old-history', 'Stale server answer'));
    await loading;

    expect(harness.controller.messages, hasLength(2));
    expect(harness.controller.messages.first.text, 'Send before history');
    expect(harness.controller.messages.last.outputKind,
        AiAssistantOutputKind.thinking);
    expect(harness.controller.reply, same(turn));
    expect(harness.controller.replying, isTrue);
    expect(harness.controller.historyLoading, isFalse);
    expect(harness.controller.historyLoaded, isTrue);
    expect(notifications, beforeLateHistory);
  });

  test('fragmented SSE updates only the live row and done flushes all tokens',
      () {
    fakeAsync((clock) {
      final harness = AiControllerTestHarness();
      try {
        var pageNotifications = 0;
        harness.controller.addListener(() => pageNotifications++);
        _send(harness.controller, clock, 'Question');
        final reply = harness.controller.reply!;
        final userRow = harness.controller.messages.first;
        final baseAssistantRow = harness.controller.messages.last;
        var liveNotifications = 0;
        reply.visible.addListener(() => liveNotifications++);
        final afterSend = pageNotifications;

        final stream = harness.api.turns.single;
        stream.fragment('event: del');
        stream.fragment('ta\ndata: {"text":" A 中');
        clock.flushMicrotasks();
        expect(reply.text.toString(), isEmpty);
        stream.fragment('文 "}\n');
        stream.fragment('\n');
        stream.delta('🙂');
        clock.flushMicrotasks();
        expect(reply.visible.value.outputKind, AiAssistantOutputKind.thinking);
        expect(liveNotifications, 0);
        clock.elapse(const Duration(milliseconds: 40));
        clock.flushMicrotasks();

        expect(reply.visible.value.text, ' A 中文 🙂');
        expect(liveNotifications, 1);
        expect(pageNotifications, afterSend);
        expect(harness.controller.messages.first, same(userRow));
        expect(harness.controller.messages.last, same(baseAssistantRow));

        stream.delta('\nlast token');
        stream.done();
        clock.flushMicrotasks();
        expect(harness.controller.messages.last.text, ' A 中文 🙂\nlast token');
        expect(harness.controller.messages.last.status, 'complete');
        expect(harness.controller.replying, isFalse);
        expect(stream.token!.isCancelled, isTrue);
        expect(pageNotifications, afterSend + 1);
        final completeNotifications = liveNotifications;
        clock.elapse(const Duration(milliseconds: 100));
        expect(liveNotifications, completeNotifications);
      } finally {
        harness.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  test('stopped buffered turn cannot publish or fail a subsequent live turn',
      () {
    fakeAsync((clock) {
      final harness = AiControllerTestHarness();
      try {
        _send(harness.controller, clock, 'First');
        final oldReply = harness.controller.reply!;
        final oldStream = harness.api.turns.single;
        oldStream.delta('First buffered answer');
        clock.flushMicrotasks();
        harness.controller.stopReply();
        expect(oldReply.terminal, isTrue);
        expect(oldStream.token!.isCancelled, isTrue);
        expect(harness.controller.messages.last.text, 'First buffered answer');
        expect(harness.controller.messages.last.status, 'stopped');
        final stoppedRow = harness.controller.messages.last;

        _send(harness.controller, clock, 'Second');
        final newReply = harness.controller.reply!;
        final newStream = harness.api.turns.last;
        oldReply.append(' obsolete timer text');
        oldStream.events.addError(
            const AiAssistantException('OLD_FAILURE', 'Obsolete failure'));
        clock.flushMicrotasks();
        newStream.delta('Second answer');
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 40));
        clock.flushMicrotasks();

        expect(harness.controller.reply, same(newReply));
        expect(harness.controller.replying, isTrue);
        expect(harness.controller.error, isNull);
        expect(newReply.visible.value.text, 'Second answer');
        expect(harness.controller.messages[1], same(stoppedRow));
        expect(harness.controller.messages[1].text, 'First buffered answer');
        newStream.done();
        clock.flushMicrotasks();
        expect(harness.controller.messages.last.text, 'Second answer');
        expect(harness.controller.messages.last.status, 'complete');
      } finally {
        harness.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  test('an unexpected stream failure preserves buffered partial text', () {
    fakeAsync((clock) {
      final harness = AiControllerTestHarness();
      try {
        _send(harness.controller, clock, 'Question');
        final turn = harness.api.turns.single;
        turn.delta('Buffered answer');
        clock.flushMicrotasks();
        expect(harness.controller.reply!.visible.value.text, isNull);
        turn.events.addError(StateError('Unexpected transport failure'));
        clock.flushMicrotasks();
        expect(harness.controller.messages.last.text, 'Buffered answer');
        expect(harness.controller.messages.last.status, 'failed');
        expect(harness.controller.replying, isFalse);
        expect(turn.token!.isCancelled, isTrue);
        clock.elapse(const Duration(milliseconds: 100));
        expect(harness.controller.messages.last.text, 'Buffered answer');
      } finally {
        harness.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  test('stop before the first delta removes thinking and permits another send',
      () {
    fakeAsync((clock) {
      final harness = AiControllerTestHarness();
      try {
        _send(harness.controller, clock, 'First');
        final oldStream = harness.api.turns.single;
        harness.controller.stopReply();
        expect(harness.controller.messages, hasLength(1));
        expect(harness.controller.messages.single.role, AiAssistantRole.user);
        _send(harness.controller, clock, 'Second');
        final newReply = harness.controller.reply!;
        oldStream.delta('Late first answer');
        oldStream.done();
        clock.flushMicrotasks();
        expect(harness.controller.reply, same(newReply));
        expect(harness.controller.messages, hasLength(3));
        expect(newReply.text.toString(), isEmpty);
        expect(harness.controller.replying, isTrue);
      } finally {
        harness.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  for (final sameAccount in [false, true]) {
    test(
        'late history is rejected after ${sameAccount ? 'token' : 'account'} change',
        () async {
      final harness = AiControllerTestHarness();
      addTearDown(harness.dispose);
      final pending = Completer<AiAssistantHistoryPage>();
      harness.api.onHistory = () => pending.future;
      final loading = harness.controller.loadHistory();
      harness.changeSession(sameAccount: sameAccount);
      expect(harness.api.historyTokens.single!.isCancelled, isTrue);
      pending.complete(aiControllerHistory('old-owner', 'Private old answer'));
      await loading;
      expect(harness.controller.current, isFalse);
      expect(harness.controller.messages, isEmpty);
      expect(harness.controller.historyLoading, isFalse);
      expect(harness.controller.hasMore, isFalse);
      expect(harness.controller.error, isNull);
      expect(await harness.controller.send('Wrong account'), isFalse);
    });
  }

  test('session change clears rows and cancels a pending live publication', () {
    fakeAsync((clock) {
      final harness = AiControllerTestHarness();
      try {
        _send(harness.controller, clock, 'Private question');
        final reply = harness.controller.reply!;
        final stream = harness.api.turns.single;
        var liveNotifications = 0;
        reply.visible.addListener(() => liveNotifications++);
        stream.delta('Private unpublished answer');
        clock.flushMicrotasks();
        expect(liveNotifications, 0);
        harness.changeSession();
        final afterSessionChange = liveNotifications;
        expect(reply.terminal, isTrue);
        expect(stream.token!.isCancelled, isTrue);
        expect(harness.controller.messages, isEmpty);

        stream.delta('Old private continuation');
        stream.done();
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 100));
        clock.flushMicrotasks();
        expect(liveNotifications, afterSessionChange);
        expect(harness.controller.messages, isEmpty);
        expect(harness.controller.replying, isFalse);
        expect(harness.controller.error, isNull);
      } finally {
        harness.dispose();
        clock.flushMicrotasks();
      }
    });
  });
}
