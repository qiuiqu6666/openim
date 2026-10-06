import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/customer_service_controller.dart';
import 'package:openim/pages/customer_service/data/data.dart';
import 'package:openim/pages/customer_service/models/customer_service_chat_entry.dart';

import 'customer_service_test_fakes.dart';

Future<void> _flush() async {
  for (var turn = 0; turn < 5; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('guest construction is independent of an uninitialized OpenIM profile',
      () {
    final controller = CustomerServiceController.forCurrentAccount(guest: true);
    expect(controller.name, '访客');
    expect(controller.avatarUrl, isEmpty);
    expect(controller.sessionStore.accountId, isEmpty);
    controller.dispose();
  });

  test('sending during history load survives late history and server echo',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    final history = Completer<List<CustomerServiceMessage>>();
    harness.api.onList = () => history.future;
    final loading = harness.controller.initialize();
    await _flush();
    expect(harness.controller.loading, isTrue);
    expect(harness.controller.historyReady, isFalse);
    await harness.controller.sendText('  A question while loading  ');
    final sent = harness.controller.entries.single;
    expect(sent.content, 'A question while loading');
    expect(sent.state, CustomerServiceSendState.sent);
    harness.cable.message(sent.message!);
    history.complete([
      customerServiceTestMessage('10', 'Previous answer',
          createdAt: DateTime.utc(2025, 12, 31)),
    ]);
    await loading;
    expect(harness.controller.entries.map((entry) => entry.content),
        ['Previous answer', 'A question while loading']);
    expect(harness.controller.entries.last.echoId, sent.echoId);
    expect(harness.controller.loading, isFalse);
    expect(harness.controller.historyReady, isTrue);
    expect(harness.controller.showFaq, isFalse);
    expect(harness.cable.connections, hasLength(1));
  });

  test(
      'echo and server ID deduplicate acknowledgments and updates replace content',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    final response = Completer<CustomerServiceMessage>();
    harness.api.onSend = (_) => response.future;
    final sending = harness.controller.sendText('My question');
    await _flush();
    final echo = harness.api.sends.single.echoId;
    final message =
        customerServiceTestMessage('101', 'My question', echoId: echo, type: 0);
    harness.cable.message(message);
    response.complete(message);
    await sending;
    expect(harness.controller.entries, hasLength(1));
    harness.cable.message(
        customerServiceTestMessage('101', 'Updated response', type: 0));
    expect(harness.controller.entries, hasLength(1));
    expect(harness.controller.entries.single.content, 'Updated response');
    expect(harness.controller.entries.single.echoId, echo);
    harness.cable.message(customerServiceTestMessage(
        '102', 'Another conversation',
        conversationId: '43'));
    expect(harness.controller.entries, hasLength(1));
  });

  test('failed sends retry the same local entry and echo', () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    harness.api.onSend = (_) async => throw StateError('offline');
    await harness.controller.sendText('Please help');
    final failed = harness.controller.entries.single;
    expect(failed.state, CustomerServiceSendState.failed);
    expect(failed.content, 'Please help');
    harness.api.onSend = null;
    await harness.controller.retry(failed);
    expect(harness.controller.entries, hasLength(1));
    expect(
        harness.controller.entries.single.state, CustomerServiceSendState.sent);
    expect(harness.api.sends.map((send) => send.echoId),
        [failed.echoId, failed.echoId]);
    await harness.controller.retry(harness.controller.entries.single);
    expect(harness.api.sends, hasLength(2));
  });

  test('an ID-only acknowledgment keeps local text and marks the send complete',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    harness.api.onSend = (_) async => customerServiceTestMessage('201', '');
    await harness.controller.sendText('Keep my question');
    final entry = harness.controller.entries.single;
    expect(entry.message!.id, '201');
    expect(entry.content, 'Keep my question');
    expect(entry.echoId, harness.api.sends.single.echoId);
    expect(entry.state, CustomerServiceSendState.sent);
    harness.cable.message(customerServiceTestMessage('202', ''));
    expect(harness.controller.entries, hasLength(1));
  });

  test(
      'an echo-less socket upload before REST folds both matches and keeps the local file',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    final directory =
        await Directory.systemTemp.createTemp('support-controller-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/attachment.png').writeAsBytes([1]);
    final upload = CustomerServiceUpload(
        path: file.path, filename: 'attachment.png', fileType: 'image');
    final response = Completer<CustomerServiceMessage>();
    final started = Completer<String>();
    harness.api.onAttachment = (echo) {
      started.complete(echo);
      return response.future;
    };
    await harness.controller.initialize();
    final sending = harness.controller.sendUpload(upload);
    final echo = await started.future;
    final socket = CustomerServiceMessage(
        id: '201',
        content: '',
        messageType: 0,
        echoId: '',
        conversationId: '42',
        attachments: const [
          CustomerServiceAttachment(
              fileType: 'image',
              dataUrl: 'https://support.invalid/image.png',
              thumbUrl: '',
              fileName: 'attachment.png'),
        ]);
    harness.cable.message(socket);
    expect(harness.controller.entries, hasLength(2));
    response.complete(socket);
    await sending;
    expect(harness.controller.entries, hasLength(1));
    expect(harness.controller.entries.single.echoId, echo);
    expect(harness.controller.entries.single.upload, same(upload));
    expect(harness.controller.entries.single.attachments, hasLength(1));
  });

  test(
      'acknowledgments reorder by server time and numeric ID for equal timestamps',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    final first = Completer<CustomerServiceMessage>();
    final second = Completer<CustomerServiceMessage>();
    harness.api.onSend =
        (request) => request.content == 'First' ? first.future : second.future;
    final firstSend = harness.controller.sendText('First');
    final secondSend = harness.controller.sendText('Second');
    await _flush();
    final time = DateTime.utc(2026, 1, 1);
    second.complete(
        customerServiceTestMessage('102', 'Second', type: 0, createdAt: time));
    await secondSend;
    expect(harness.controller.entries.map((entry) => entry.content),
        ['Second', 'First']);
    first.complete(
        customerServiceTestMessage('101', 'First', type: 0, createdAt: time));
    await firstSend;
    expect(harness.controller.entries.map((entry) => entry.content),
        ['First', 'Second']);
  });

  test('rapid retries with a stale failed entry make one new request',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    harness.api.onSend = (_) async => throw StateError('offline');
    await harness.controller.sendText('Retry me');
    final failed = harness.controller.entries.single;
    final response = Completer<CustomerServiceMessage>();
    harness.api.onSend = (_) => response.future;
    final firstRetry = harness.controller.retry(failed);
    final staleRetry = harness.controller.retry(failed);
    await _flush();
    expect(harness.api.sends, hasLength(2));
    response.complete(customerServiceTestMessage('101', 'Retry me',
        echoId: failed.echoId, type: 0));
    await Future.wait([firstRetry, staleRetry]);
    await harness.controller.retry(failed);
    expect(harness.api.sends, hasLength(2));
    expect(harness.controller.entries, hasLength(1));
  });

  test('history failure leaves FAQs and sends usable, retry clears the error',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    harness.api.onList = () async => throw StateError('offline');
    await harness.controller.initialize();
    expect(harness.controller.error, 'connection');
    expect(harness.controller.historyReady, isTrue);
    expect(harness.controller.showFaq, isTrue);
    expect(harness.controller.canSend, isTrue);
    harness.api.onList = null;
    await harness.controller.initialize();
    expect(harness.controller.error, isNull);
    expect(harness.controller.loading, isFalse);
    expect(harness.api.listCalls, 2);
    expect(harness.cable.connections, hasLength(1));
  });

  test(
      'an account change rejects pending session completion and all late callbacks',
      () async {
    final officialURL = Completer<String>();
    final harness =
        CustomerServiceTestHarness(officialURLLoader: () => officialURL.future);
    addTearDown(harness.dispose);
    final session = Completer<CustomerServiceSession>();
    harness.store.onEnsure = () => session.future;
    var notifications = 0;
    harness.controller.addListener(() => notifications++);
    final loading = harness.controller.initialize();
    await _flush();
    harness.active = false;
    final before = notifications;
    session.complete(customerServiceTestSession);
    officialURL.complete('https://official.invalid');
    await loading;
    await harness.controller.sendText('Must not send');
    harness.cable.message(customerServiceTestMessage('1', 'Stale answer'));
    harness.cable.typing(true);
    harness.controller.resume();
    expect(harness.api.sends, isEmpty);
    expect(harness.api.listCalls, 0);
    expect(harness.cable.connections, isEmpty);
    expect(harness.cable.suspensions, greaterThan(0));
    expect(harness.controller.entries, isEmpty);
    expect(harness.controller.agentTyping, isFalse);
    expect(harness.controller.canSend, isFalse);
    expect(harness.controller.officialURL, isEmpty);
    expect(notifications, before);
  });

  test('dispose cancels publication of pending sends and official URL',
      () async {
    final officialURL = Completer<String>();
    final harness =
        CustomerServiceTestHarness(officialURLLoader: () => officialURL.future);
    await harness.controller.initialize();
    final response = Completer<CustomerServiceMessage>();
    harness.api.onSend = (_) => response.future;
    var notifications = 0;
    harness.controller.addListener(() => notifications++);
    final sending = harness.controller.sendText('Pending send');
    await _flush();
    final before = notifications;
    harness.dispose();
    response.complete(customerServiceTestMessage('101', 'Pending send',
        echoId: harness.api.sends.single.echoId, type: 0));
    officialURL.complete('https://official.invalid');
    await sending;
    await _flush();
    await harness.controller.sendText('After close');
    harness.cable.typing(true);
    harness.cable.message(customerServiceTestMessage('102', 'After close'));
    expect(notifications, before);
    expect(harness.api.sends, hasLength(1));
    expect(harness.controller.entries.single.message, isNull);
    expect(harness.controller.officialURL, isEmpty);
    expect(harness.api.disposed, isTrue);
    expect(harness.store.disposed, isTrue);
    expect(harness.cable.disposed, isTrue);
  });

  testWidgets(
      'typing expires, suspension clears it, and resume reattaches once',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    await harness.controller.initialize();
    harness.cable.typing(true);
    expect(harness.controller.agentTyping, isTrue);
    await tester.pump(const Duration(seconds: 7));
    expect(harness.controller.agentTyping, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(harness.controller.agentTyping, isFalse);
    harness.cable.typing(true);
    harness.controller.suspend();
    expect(harness.controller.agentTyping, isFalse);
    harness.cable.typing(true);
    expect(harness.controller.agentTyping, isFalse);
    harness.controller.resume();
    harness.controller.resume();
    expect(harness.cable.connections, hasLength(2));
    expect(harness.cable.suspensions, 1);
    harness.cable.typing(true);
    harness.dispose();
    await tester.pump(const Duration(seconds: 8));
    expect(tester.takeException(), isNull);
  });

  test(
      'an account change clears typing and closes callbacks without notifying the old page',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    harness.cable.typing(true);
    var notifications = 0;
    harness.controller.addListener(() => notifications++);
    harness.active = false;
    harness.cable.message(customerServiceTestMessage('1', 'Stale answer'));
    expect(harness.controller.agentTyping, isFalse);
    expect(harness.cable.suspensions, 1);
    expect(notifications, 0);
  });

  test(
      'connection confirmation merges fresh history without losing existing sends',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    await harness.controller.sendText('Existing question');
    harness.api.history = [
      customerServiceTestMessage('90', 'An agent answer',
          createdAt: DateTime.utc(2025, 12, 31)),
      harness.controller.entries.single.message!,
    ];
    harness.controller.suspend();
    harness.controller.resume();
    harness.cable.connected();
    await _flush();
    expect(harness.api.listCalls, 2);
    expect(harness.controller.entries.map((entry) => entry.content),
        ['An agent answer', 'Existing question']);
  });

  test(
      'connection confirmation during a history request performs a fresh pull afterwards',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    final firstHistory = Completer<List<CustomerServiceMessage>>();
    harness.api.onList = () => harness.api.listCalls == 1
        ? firstHistory.future
        : Future.value(
            [customerServiceTestMessage('2', 'Reply after reconnect')]);
    final initial = harness.controller.initialize();
    await _flush();
    harness.cable.connected();
    await _flush();
    expect(harness.api.listCalls, 1);
    firstHistory.complete([]);
    await initial;
    await _flush();
    expect(harness.api.listCalls, 2);
    expect(harness.controller.entries.single.content, 'Reply after reconnect');
  });

  testWidgets('HTTP fallback polls after 15 seconds with one request in flight',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    await harness.controller.initialize();
    final pending = Completer<List<CustomerServiceMessage>>();
    harness.api.onList = () => pending.future;
    await tester.pump(const Duration(seconds: 14));
    expect(harness.api.listCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(harness.api.listCalls, 2);
    await tester.pump(const Duration(seconds: 30));
    expect(harness.api.listCalls, 2);
    pending.complete([customerServiceTestMessage('2', 'HTTP agent reply')]);
    await tester.pump();
    expect(harness.controller.entries.single.content, 'HTTP agent reply');
    harness.api.onList = null;
    await tester.pump(const Duration(seconds: 15));
    expect(harness.api.listCalls, 3);
    harness.dispose();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.api.listCalls, 3);
  });

  testWidgets(
      'confirmation cancels fallback and disconnection restarts it once',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    await harness.controller.initialize();
    harness.cable.connected();
    await tester.pump(const Duration(milliseconds: 1));
    expect(harness.api.listCalls, 2);
    await tester.pump(const Duration(seconds: 45));
    expect(harness.api.listCalls, 2);
    harness.cable.disconnect();
    harness.cable.disconnect();
    await tester.pump(const Duration(seconds: 14));
    expect(harness.api.listCalls, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(harness.api.listCalls, 3);
    harness.cable.connected();
    await tester.pump(const Duration(milliseconds: 1));
    expect(harness.api.listCalls, 4);
    await tester.pump(const Duration(seconds: 30));
    expect(harness.api.listCalls, 4);
    harness.dispose();
  });

  testWidgets('suspension and account changes stop HTTP fallback until resume',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    await harness.controller.initialize();
    await tester.pump(const Duration(seconds: 15));
    expect(harness.api.listCalls, 2);
    harness.controller.suspend();
    harness.cable.disconnect();
    harness.cable.connected();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.api.listCalls, 2);
    harness.controller.resume();
    harness.controller.resume();
    expect(harness.cable.connections, hasLength(2));
    await tester.pump(const Duration(seconds: 15));
    expect(harness.api.listCalls, 3);
    harness.active = false;
    await tester.pump(const Duration(seconds: 30));
    expect(harness.api.listCalls, 3);
    harness.dispose();
  });

  testWidgets('disposing ignores an outstanding fallback response',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    await harness.controller.initialize();
    final pending = Completer<List<CustomerServiceMessage>>();
    harness.api.onList = () => pending.future;
    await tester.pump(const Duration(seconds: 15));
    expect(harness.api.listCalls, 2);
    var notifications = 0;
    harness.controller.addListener(() => notifications++);
    harness.dispose();
    pending.complete([customerServiceTestMessage('3', 'Reply after closure')]);
    await tester.pump(const Duration(seconds: 30));
    expect(harness.api.listCalls, 2);
    expect(harness.controller.entries, isEmpty);
    expect(notifications, 0);
  });
}
