import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/message_notification_target.dart';
import 'package:openim/core/notifications/notification_lookup_pool.dart';

MessageNotificationTarget target(String id) => MessageNotificationTarget(
      accountID: 'me',
      sessionKey: 'session',
      conversationID: id,
      sourceID: id,
      sessionType: 1,
    );
void main() {
  test(
      'sequential messages share metadata; callback and session clear take priority',
      () async {
    var reads = 0;
    final pool = NotificationLookupPool((_) async {
      reads++;
      return ConversationInfo(conversationID: 'group', recvMsgOpt: 0);
    }, cacheDuration: const Duration(seconds: 1));
    for (var i = 0; i < 1200; i++) {
      await pool.read(target('group'));
    }
    expect(reads, 1);
    pool.seed(
        'session',
        ConversationInfo(
            conversationID: 'group',
            userID: 'group',
            conversationType: 1,
            recvMsgOpt: 2));
    expect((await pool.read(target('group')))!.recvMsgOpt, 2);
    pool.clear();
    await pool.read(target('group'));
    expect(reads, 2);
  });
  test(
      'seeded queued job never starts and stale result cannot replace callback',
      () async {
    final pending = Completer<ConversationInfo>();
    var reads = 0;
    final pool = NotificationLookupPool((_) {
      reads++;
      return pending.future;
    }, concurrency: 1, cacheDuration: const Duration(seconds: 1));
    final first = pool.read(target('a'));
    final queued = pool.read(target('b'));
    for (final id in ['a', 'b']) {
      pool.seed(
          'session',
          ConversationInfo(
              conversationID: id,
              userID: id,
              conversationType: 1,
              recvMsgOpt: 2));
    }
    expect((await first)!.recvMsgOpt, 2);
    expect((await queued)!.recvMsgOpt, 2);
    pending.complete(ConversationInfo(conversationID: 'a', recvMsgOpt: 0));
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    expect((await pool.read(target('a')))!.recvMsgOpt, 2);
  });

  test(
      'shares in-flight queries and bounds a 1000-source burst to four native calls',
      () async {
    final queries = <Completer<ConversationInfo>>[];
    final pool = NotificationLookupPool((_) {
      final query = Completer<ConversationInfo>();
      queries.add(query);
      return query.future;
    });
    final first = pool.read(target('same'));
    expect(identical(first, pool.read(target('same'))), isTrue);
    final requests = [
      first,
      for (var i = 0; i < 1000; i++) pool.read(target('c$i'))
    ];
    expect(queries.length, 4);
    pool.clear();
    expect(
        (await Future.wait(requests)).every((value) => value == null), isTrue);
    for (final query in queries) {
      query.complete(ConversationInfo(conversationID: 'old'));
    }
    await Future<void>.delayed(Duration.zero);
    final next = pool.read(target('new'));
    expect(queries.length, 5);
    queries.last.complete(ConversationInfo(conversationID: 'new'));
    expect((await next)!.conversationID, 'new');
  });
}
