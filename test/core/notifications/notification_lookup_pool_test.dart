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
