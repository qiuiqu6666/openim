import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/chat_history_cache.dart';

import 'support/revocation_fixture.dart';

void main() {
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  for (final exit in ['open', 'closed', 'account', 'reset']) {
    test('accepted recall fences stale picture after $exit', () async {
      final f = RevocationFixture();
      final photo = f.message(sender: 'admin', ageSeconds: 1)
        ..contentType = MessageType.picture
        ..pictureElem = PictureElem();
      final pending = Completer<void>();
      f.onRevoke = () => pending.future;
      ChatHistoryCache.write('admin', f.conversation, [photo]);
      final task = f.controller.revokeMessage(photo);
      expect(f.requests, hasLength(1));
      if (exit == 'closed') f.closed = true;
      if (exit == 'account') f.account = 'other';
      if (exit == 'reset') ChatHistoryCache.clear();
      pending.complete();
      await task;
      // Simulate a prior route or native read completing after success.
      ChatHistoryCache.write('admin', 'sg_group', [photo]);
      final row = ChatHistoryCache.read('admin', 'sg_group').single;
      final acceptedSession = exit == 'open' || exit == 'closed';
      expect(
          row.contentType,
          acceptedSession
              ? MessageType.revokeMessageNotification
              : MessageType.picture);
      if (acceptedSession) expect(row.pictureElem, isNull);
      if (exit != 'open') expect(f.removed, isEmpty);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('reentry first frame after disposed recall in $brightness',
        (tester) async {
      final f = RevocationFixture();
      final photo = f.message(sender: 'admin', ageSeconds: 1)
        ..contentType = MessageType.picture
        ..pictureElem = PictureElem();
      final pending = Completer<void>();
      f.onRevoke = () => pending.future;
      ChatHistoryCache.write('admin', f.conversation, [photo],
          readySession: ('admin', OpenIM.iMManager.token));
      final task = f.controller.revokeMessage(photo);
      f.closed = true;
      pending.complete();
      await task;
      final history = Completer<AdvancedMessage>();
      final timeline = ChatTimelineController(
        accountID: 'admin',
        currentAccountID: () => 'admin',
        conversation: () =>
            ConversationInfo(conversationID: f.conversation, latestMsg: photo),
        fetchDisplaySnapshot: () async => [photo],
        fetch: ({required count, startMsg}) => history.future,
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {},
      );
      addTearDown(timeline.close);
      timeline.initialize();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Obx(() => Column(children: [
              for (final row in timeline.messageList)
                Text(row.contentType == MessageType.picture ? '原图片' : '撤回提示'),
            ])),
      ));
      expect(find.text('原图片'), findsNothing);
      expect(find.text('撤回提示'), findsOneWidget);
      history.complete(AdvancedMessage(messageList: [photo], isEnd: true));
      await tester.pump();
      expect(find.text('原图片'), findsNothing);
      expect(find.text('撤回提示'), findsOneWidget);
      timeline.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('failed recall retains original picture', () async {
    final f = RevocationFixture();
    final photo = f.message(sender: 'admin', ageSeconds: 1)
      ..contentType = MessageType.picture
      ..pictureElem = PictureElem();
    f.onRevoke = () async => throw StateError('offline');
    await f.controller.revokeMessage(photo);
    expect(ChatHistoryCache.applyRevocation('admin', photo).pictureElem,
        isNotNull);
  });
}
