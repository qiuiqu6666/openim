import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/conversation_reads/conversation_read_recovery.dart';
import 'package:openim/core/conversation_reads/conversation_read_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> calls;
  late bool active;
  late int failures;

  ConversationReadRequest request(Iterable<String> ids) =>
      ConversationReadRequest.capture(
          ConversationInfo(conversationID: 'chat', unreadCount: ids.length),
          retryMessageIDs: ids);

  setUp(() {
    OpenIM.iMManager.userID = 'self';
    calls = [];
    active = true;
    failures = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failures-- > 0) throw PlatformException(code: 'NETWORK_FAILURE');
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    OpenIM.iMManager.userID = 'self';
  });

  test('recovery uses immutable captured IDs and never the full-clear API',
      () async {
    final ids = ['seen', 'seen'];
    final captured = request(ids);
    ids.add('unseen-after-exit');
    await ConversationReadRecovery().recover(captured, isCurrent: () => active);
    expect(calls.single.method, 'markMessagesAsReadByMsgID');
    expect((calls.single.arguments as Map)['messageIDList'], ['seen']);
  });

  test('an empty safe boundary does not fall back to clearing the conversation',
      () async {
    await ConversationReadRecovery()
        .recover(request([]), isCurrent: () => true);
    expect(calls, isEmpty);
  });

  test('captured account ownership prevents recovery into a replacement login',
      () async {
    final captured = request(['seen']);
    OpenIM.iMManager.userID = 'another-account';
    await ConversationReadRecovery().recover(captured, isCurrent: () => true);
    expect(calls, isEmpty);
  });

  testWidgets('one transient failure retries the same IDs after a delay',
      (tester) async {
    failures = 1;
    final done = ConversationReadRecovery()
        .recover(request(['seen']), isCurrent: () => active);
    await tester.pump();
    expect(calls, hasLength(1));
    await tester.pump(ConversationReadRecovery.retryDelay);
    await done;
    expect(calls, hasLength(2));
    expect((calls.last.arguments as Map)['messageIDList'], ['seen']);
  });

  testWidgets('persistent failure stops after two attempts', (tester) async {
    failures = 10;
    Object? error;
    final done = ConversationReadRecovery()
        .recover(request(['seen']), isCurrent: () => active)
        .catchError((Object e) {
      error = e;
    });
    await tester.pump();
    await tester.pump(ConversationReadRecovery.retryDelay);
    await done;
    await tester.pump(const Duration(seconds: 5));
    expect(error, isA<PlatformException>());
    expect(calls, hasLength(2));
  });

  testWidgets('account or list invalidation during backoff cancels the retry',
      (tester) async {
    failures = 1;
    final done = ConversationReadRecovery()
        .recover(request(['seen']), isCurrent: () => active);
    await tester.pump();
    active = false;
    await tester.pump(ConversationReadRecovery.retryDelay);
    await done;
    expect(calls, hasLength(1));
  });

  test('batches remain bounded to the captured ID set', () async {
    final ids = List.generate(205, (i) => 'seen-$i');
    await ConversationReadRecovery()
        .recover(request(ids), isCurrent: () => true);
    expect(calls, hasLength(3));
    final batches =
        calls.map((call) => (call.arguments as Map)['messageIDList'] as List);
    expect(batches.map((batch) => batch.length), [100, 100, 5]);
    expect(batches.expand((batch) => batch), ids);
  });
}
