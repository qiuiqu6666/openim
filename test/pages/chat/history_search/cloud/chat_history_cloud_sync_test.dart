import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/cloud/chat_history_cloud_sync.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_controller.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';

Message msg(String id) =>
    Message(clientMsgID: id, sendID: 'alice', contentType: MessageType.text);

class Source implements ChatHistorySearchSource, ChatHistoryCloudSource {
  int supplements = 0;
  bool fail = false;
  @override
  bool get cloudHasMore => supplements < 2;
  @override
  Future<void> supplement(String id, bool Function() current) async {
    if (fail) throw StateError('offline');
    if (current()) supplements++;
  }

  @override
  Future<List<Message>> search(
          {required String conversationID,
          required ChatHistorySearchQuery query,
          required int pageIndex,
          int count = 30}) async =>
      [msg('local'), if (supplements == 2) msg('cloud')];
}

void main() {
  test('pages SDK history from oldest cursor and stops only at isEnd',
      () async {
    final cursors = <String?>[];
    final sync = ChatHistoryCloudSync((id, cursor, count) async {
      expect(id, 'group');
      expect(count, 100);
      cursors.add(cursor?.clientMsgID);
      return AdvancedMessage(
          messageList: [msg('old-${cursors.length}')],
          errCode: 0,
          isEnd: cursors.length == 2);
    });
    await sync.load('group', () => true);
    expect(sync.hasMore, isTrue);
    await sync.load('group', () => true);
    await sync.load('group', () => true);
    expect(cursors, [null, 'old-1']);
    expect(sync.hasMore, isFalse);
  });
  test('stale response cannot advance cursor', () async {
    final response = Completer<AdvancedMessage>();
    var current = true;
    final sync = ChatHistoryCloudSync((_, __, ___) => response.future);
    final task = sync.load('group', () => current);
    current = false;
    response
        .complete(AdvancedMessage(messageList: [], isEnd: true, errCode: 0));
    await task;
    expect(sync.hasMore, isTrue);
  });
  test('empty nonterminal and business errors remain retryable', () async {
    for (final code in [0, 1001]) {
      final sync = ChatHistoryCloudSync((_, __, ___) async =>
          AdvancedMessage(messageList: [], isEnd: false, errCode: code));
      await expectLater(sync.load('group', () => true), throwsStateError);
      expect(sync.hasMore, isTrue);
    }
  });
  test('same cursor does not loop forever', () async {
    final sync = ChatHistoryCloudSync((_, __, ___) async =>
        AdvancedMessage(messageList: [msg('same')], isEnd: false, errCode: 0));
    await sync.load('group', () => true);
    await expectLater(sync.load('group', () => true), throwsStateError);
  });
  test('supplements incrementally, rescans and deduplicates local results',
      () async {
    final source = Source();
    final controller =
        ChatHistorySearchController(conversationID: 'group', source: source);
    await controller.search(const ChatHistorySearchQuery(senderIDs: ['alice']));
    expect(controller.results.map((m) => m.clientMsgID), ['local']);
    expect(controller.hasMore, isTrue);
    expect(source.supplements, 1);
    await controller.loadMore();
    expect(controller.results.map((m) => m.clientMsgID), ['local', 'cloud']);
    expect(controller.hasMore, isFalse);
    controller.dispose();
  });
  test('cloud failure keeps results and retry resumes', () async {
    final source = Source();
    final controller =
        ChatHistorySearchController(conversationID: 'group', source: source);
    await controller.search(const ChatHistorySearchQuery());
    source.fail = true;
    await controller.loadMore();
    expect(controller.failed, isTrue);
    expect(controller.results.length, 1);
    source.fail = false;
    await controller.retry();
    expect(controller.failed, isFalse);
    expect(controller.results.length, 2);
    controller.dispose();
  });
}
