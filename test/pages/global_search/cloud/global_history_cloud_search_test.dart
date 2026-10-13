import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/global_search/cloud/global_history_cloud_search.dart';

Message message(String id) =>
    Message(clientMsgID: id, contentType: MessageType.text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'session';
  });
  test('starts three histories together and keeps failed history retryable',
      () async {
    final pending = <String, Completer<AdvancedMessage>>{};
    final cloud = GlobalHistoryCloudSearch(
        conversations: (_) async => List.generate(
            4, (i) => ConversationInfo(conversationID: 'chat-$i')),
        history: (id, _, __) =>
            (pending[id] = Completer<AdvancedMessage>()).future);
    final first = cloud.supplement(() => true);
    final failure = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final started = pending.keys.toList();
    for (final entry in pending.entries) {
      if (entry.key == 'chat-0') {
        entry.value.completeError(StateError('offline'));
      } else {
        entry.value.complete(AdvancedMessage(isEnd: true));
      }
    }
    await failure;
    expect(started, ['chat-0', 'chat-1', 'chat-2']);
    pending.clear();
    final retry = cloud.supplement(() => true);
    await Future<void>.delayed(Duration.zero);
    expect(pending.keys.toSet(), {'chat-0', 'chat-3'});
    for (final page in pending.values) {
      page.complete(AdvancedMessage(isEnd: true));
    }
    await retry;
    expect(cloud.hasMore, isFalse);
  });
  test('discovers conversations beyond first page and limits each batch',
      () async {
    final offsets = <int>[];
    final calls = <String>[];
    final cloud = GlobalHistoryCloudSearch(conversations: (offset) async {
      offsets.add(offset);
      return List.generate(offset == 0 ? 50 : 1,
          (i) => ConversationInfo(conversationID: 'chat-${offset + i}'));
    }, history: (id, cursor, count) async {
      expect(count, 100);
      calls.add(id);
      return AdvancedMessage(
          messageList: [message(id)], isEnd: true, errCode: 0);
    });
    await cloud.supplement(() => true);
    expect(calls.length, 3);
    expect(cloud.hasMore, isTrue);
    for (var i = 0; i < 16; i++) {
      await cloud.supplement(() => true);
    }
    expect(offsets, [0, 50]);
    expect(calls.toSet().length, 51);
    expect(cloud.hasMore, isFalse);
  });
  test('cloud error keeps cursor for retry and does not claim completion',
      () async {
    var fail = true;
    final cloud = GlobalHistoryCloudSearch(
        conversations: (_) async => [ConversationInfo(conversationID: 'group')],
        history: (_, __, ___) async {
          if (fail) throw StateError('offline');
          return AdvancedMessage(messageList: [], isEnd: true, errCode: 0);
        });
    await expectLater(cloud.supplement(() => true), throwsStateError);
    expect(cloud.hasMore, isTrue);
    fail = false;
    await cloud.supplement(() => true);
    expect(cloud.hasMore, isFalse);
  });
  test('stale discovery response schedules no history requests', () async {
    final discovery = Completer<List<ConversationInfo>>();
    var active = true;
    var calls = 0;
    final cloud = GlobalHistoryCloudSearch(
        conversations: (_) => discovery.future,
        history: (_, __, ___) async {
          calls++;
          return AdvancedMessage(isEnd: true);
        });
    final work = cloud.supplement(() => active);
    active = false;
    discovery.complete([ConversationInfo(conversationID: 'group')]);
    await work;
    expect(calls, 0);
  });
}
