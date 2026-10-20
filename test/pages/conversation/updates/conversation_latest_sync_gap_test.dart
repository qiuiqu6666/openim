import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/updates/conversation_latest_sync.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  Message message(int seq) => Message(
        clientMsgID: 'm$seq',
        seq: seq,
        contentType: MessageType.text,
        sessionType: ConversationType.single,
        sendID: 'peer',
        recvID: 'self',
      );
  ConversationInfo row(int seq) => ConversationInfo(
        conversationID: 'peer',
        userID: 'peer',
        conversationType: ConversationType.single,
        latestMsg: message(seq),
      );

  for (final returning in [false, true]) {
    testWidgets(
        '${returning ? "route return" : "message 1000"} repairs stale 998 without publishing it',
        (tester) async {
      OpenIM.iMManager.userID = 'self';
      var reads = 0;
      final published = <ConversationInfo>[];
      final sync = ConversationLatestSync(
        isActive: () => true,
        publish: published.addAll,
        flushChanges: () {},
        resolveID: (_) async => 'peer',
        read: (_) async {
          reads++;
          return [row(reads == 1 ? 998 : 1000)];
        },
      );
      addTearDown(sync.close);
      sync.observeMessage(message(1000));
      if (returning) {
        sync.requestRefresh(ConversationRefreshRequest(
            accountID: 'self', conversationID: 'peer'));
      }
      await tester.pump(ConversationLatestSync.settleDelay);
      expect(published, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(ConversationLatestSync.settleDelay);
      expect(published.single.latestMsg?.seq, 1000);
      expect(reads, 2);
    });
  }

  testWidgets('older callback during read fences then rechecks fresh query',
      (tester) async {
    OpenIM.iMManager.userID = 'self';
    var reads = 0;
    final reply = Completer<List<ConversationInfo>>();
    final published = <ConversationInfo>[];
    final sync = ConversationLatestSync(
      isActive: () => true,
      publish: published.addAll,
      flushChanges: () {},
      resolveID: (_) async => 'peer',
      read: (_) {
        reads++;
        return reply.future;
      },
    );
    addTearDown(sync.close);
    sync.observeMessage(message(1000));
    await tester.pump(ConversationLatestSync.settleDelay);
    sync.conversationsChanged(['peer']);
    sync.conversationsUpdated([row(998)]);
    reply.complete([row(1000)]);
    await tester.pump();
    expect(published, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(published.single.latestMsg?.seq, 1000);
    expect(reads, 2);
  });

  for (final kind in ['deleted', 'revoked', 'pending', 'empty']) {
    testWidgets('$kind authoritative state survives reconciliation',
        (tester) async {
      OpenIM.iMManager.userID = 'self';
      var reads = 0;
      final published = <ConversationInfo>[];
      final authoritative = row(kind == 'deleted' ? 998 : 1000)
        ..unreadCount = 7;
      if (kind == 'revoked') {
        authoritative.latestMsg!.contentType =
            MessageType.revokeMessageNotification;
      } else if (kind == 'pending') {
        authoritative.latestMsg = message(0)..status = MessageStatus.sending;
      } else if (kind == 'empty') {
        authoritative.latestMsg = null;
      }
      final sync = ConversationLatestSync(
        isActive: () => true,
        publish: published.addAll,
        flushChanges: () {},
        resolveID: (_) async => 'peer',
        read: (_) async {
          reads++;
          return [authoritative];
        },
      );
      addTearDown(sync.close);
      sync.observeMessage(message(1000));
      await tester.pump(ConversationLatestSync.settleDelay);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(ConversationLatestSync.settleDelay);
      }
      expect(published.single, same(authoritative));
      expect(published.single.unreadCount, 7);
      expect(reads, kind == 'deleted' ? 3 : 1);
    });
  }

  testWidgets('callback arriving after repaired 1000 triggers a native recheck',
      (tester) async {
    OpenIM.iMManager.userID = 'self';
    final published = <ConversationInfo>[];
    var reads = 0;
    final sync = ConversationLatestSync(
      isActive: () => true,
      publish: published.addAll,
      flushChanges: () {},
      resolveID: (_) async => 'peer',
      read: (_) async {
        reads++;
        return [row(1000)];
      },
    );
    sync.observeMessage(message(1000));
    await tester.pump(ConversationLatestSync.settleDelay);
    sync.conversationsUpdated([row(998)]);
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, 2);
    expect(published.last.latestMsg?.seq, 1000);
    sync.close();
  });
}
