import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/data/data.dart';
import 'package:openim/pages/customer_service/history/customer_service_history_merge.dart';
import 'package:openim/pages/customer_service/models/customer_service_chat_entry.dart';

import '../customer_service_test_fakes.dart';

void main() {
  test('content correction keeps stable order for undated nonnumeric IDs', () {
    final rows = mergeCustomerServiceHistory([], [
      customerServiceTestMessage('a', 'first'),
      customerServiceTestMessage('b', 'second'),
    ])!;
    final result = mergeCustomerServiceHistory(rows, [
      customerServiceTestMessage('a', 'updated'),
    ])!;
    expect(result.map((e) => e.message!.id), ['a', 'b']);
  });
  test('unchanged separately decoded history preserves rows and is silent',
      () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    harness.api.history = [customerServiceTestMessage('1', 'hello')];
    await harness.controller.initialize();
    final original = harness.controller.entries.single;
    var changes = 0;
    harness.controller.addListener(() => changes++);
    harness.api.history = [customerServiceTestMessage('1', 'hello')];
    await harness.controller.refresh();
    expect(changes, 0);
    expect(identical(harness.controller.entries.single, original), isTrue);
    harness.cable.message(customerServiceTestMessage('1', 'hello'));
    expect(changes, 0);
    harness.controller.error = 'connection';
    await harness.controller.refresh();
    expect(changes, 1);
    expect(harness.controller.error, isNull);
  });

  test('batch reconciles REST echo and early socket ID without losing upload',
      () {
    const upload = CustomerServiceUpload(
        path: '/local.jpg', filename: 'local.jpg', fileType: 'image');
    final pending = CustomerServiceChatEntry(
        echoId: 'local',
        upload: upload,
        state: CustomerServiceSendState.sending);
    final early = CustomerServiceChatEntry(
        echoId: '', message: customerServiceTestMessage('20', 'image'));
    const failed = CustomerServiceChatEntry(
        echoId: 'failed',
        text: 'retry',
        state: CustomerServiceSendState.failed);
    final result = mergeCustomerServiceHistory([
      pending,
      early,
      failed
    ], [
      customerServiceTestMessage('20', 'ack', echoId: 'local'),
      customerServiceTestMessage('10', 'old'),
      customerServiceTestMessage('20', 'updated', echoId: 'local'),
      customerServiceTestMessage('99', 'foreign', conversationId: 'other'),
    ], conversationId: '42')!;
    expect(result.map((e) => e.message?.id), ['10', '20', null]);
    expect(result[1].upload, same(upload));
    expect(result[1].content, 'updated');
    expect(result[1].state, CustomerServiceSendState.sent);
    expect(result.last, same(failed));
  });

  test('attachment-only updates and timestamp corrections are not discarded',
      () {
    CustomerServiceMessage message(String url, int second) =>
        CustomerServiceMessage(
            id: '1',
            content: '',
            messageType: 1,
            echoId: '',
            createdAt: DateTime.utc(2026).add(Duration(seconds: second)),
            attachments: [
              CustomerServiceAttachment(
                  fileType: 'image',
                  dataUrl: url,
                  thumbUrl: '',
                  fileName: 'image.jpg')
            ]);
    final rows = mergeCustomerServiceHistory([], [message('a', 5)])!;
    expect(mergeCustomerServiceHistory(rows, [message('a', 5)]), isNull);
    final changed = mergeCustomerServiceHistory(rows, [message('b', 1)])!;
    expect(changed.single.attachments.single.dataUrl, 'b');
    expect(changed.single.message!.createdAt,
        DateTime.utc(2026).add(const Duration(seconds: 1)));
  });

  test('unsorted batch uses chronology and publishes exactly once', () async {
    final harness = CustomerServiceTestHarness();
    addTearDown(harness.dispose);
    await harness.controller.initialize();
    var changes = 0;
    harness.controller.addListener(() => changes++);
    harness.api.history = List.generate(
        5000,
        (i) => customerServiceTestMessage('${5000 - i}', 'message',
            createdAt: DateTime.utc(2026).add(Duration(seconds: 5000 - i))));
    await harness.controller.refresh();
    expect(changes, 1);
    expect(harness.controller.entries.first.message!.id, '1');
    expect(harness.controller.entries.last.message!.id, '5000');
    await harness.controller.refresh();
    expect(changes, 1);
  });
}
