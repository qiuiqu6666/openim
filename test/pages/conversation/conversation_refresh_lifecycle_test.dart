import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/home/home_logic.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void onClose() {
    close();
    super.onClose();
  }
}

class _Home extends GetxController implements HomeLogic {
  @override
  final conversationsAtFirstPage = <ConversationInfo>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationInfo _conversation(String id, int time) => ConversationInfo(
      conversationID: id,
      userID: id,
      latestMsgSendTime: time,
      draftTextTime: 0,
    );
Future<void> _flush() => Future<void>.delayed(Duration.zero);
String _json(List<ConversationInfo> rows) =>
    jsonEncode(rows.map((e) => e.toJson()).toList());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late List<Completer<String>> replies;
  Completer<void>? deletion;
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
    Get.put<HomeLogic>(_Home());
    replies = [];
    deletion = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      if (call.method == 'deleteConversationAndDeleteAllMsg')
        return deletion?.future ?? Future.value();
      expect(call.method, 'getConversationListSplit');
      final reply = Completer<String>();
      replies.add(reply);
      return reply.future;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
  });

  test('a normal refresh merges SDK callbacks newer than its snapshot',
      () async {
    final logic = ConversationLogic();
    logic.list.add(_conversation('chat', 1));
    final refresh = logic.onRefresh();
    await _flush();
    logic.onChanged([_conversation('chat', 2), _conversation('added', 3)]);
    replies.single.complete(_json([_conversation('chat', 1)]));
    await refresh;
    expect(logic.list.map((e) => e.conversationID), ['added', 'chat']);
    expect(logic.list.last.latestMsgSendTime, 2);
    logic.onClose();
  });

  test('an earlier refresh cannot replace the latest completed refresh',
      () async {
    final logic = ConversationLogic();
    final old = logic.onRefresh();
    await _flush();
    final current = logic.onRefresh();
    await _flush();
    expect(logic.canShowEmptyFeed, isFalse);
    replies[1].complete(_json([_conversation('new', 2)]));
    await current;
    expect(logic.canShowEmptyFeed, isTrue);
    replies[0].complete(_json([_conversation('old', 1)]));
    await old;
    expect(logic.canShowEmptyFeed, isTrue);
    expect(logic.list.single.conversationID, 'new');
    logic.onClose();
  });

  test('an empty feed waits for a successful list read after a failure',
      () async {
    final logic = ConversationLogic();
    final first = logic.getFirstPage();
    await _flush();
    expect(logic.canShowEmptyFeed, isFalse);
    replies.single.completeError(PlatformException(code: 'read-failed'));
    await first;
    expect(logic.list, isEmpty);
    expect(logic.canShowEmptyFeed, isFalse);

    final retry = logic.onRefresh();
    await _flush();
    expect(logic.canShowEmptyFeed, isFalse);
    replies.last.complete(_json([]));
    await retry;
    expect(logic.canShowEmptyFeed, isTrue);
    logic.onClose();
  });

  for (final stop in ['clear', 'close', 'account']) {
    test('a pending refresh cannot restore rows after $stop', () async {
      final logic = ConversationLogic();
      final refresh = logic.onRefresh();
      await _flush();
      switch (stop) {
        case 'clear':
          logic.clearConversations();
        case 'close':
          logic.onClose();
        case 'account':
          OpenIM.iMManager.userID = 'other';
      }
      replies.single.complete(_json([_conversation('late', 1)]));
      await refresh;
      expect(logic.list, isEmpty);
      if (stop != 'close') logic.onClose();
    });
  }

  test(
      'initial first-page request is started by the page instead of blocking navigation',
      () async {
    final logic = ConversationLogic();
    final firstPage = logic.getFirstPage();
    await _flush();
    expect(replies, hasLength(1));
    logic.onChanged([_conversation('live', 2)]);
    replies.single.complete(_json([_conversation('snapshot', 1)]));
    await firstPage;
    expect(logic.list.map((e) => e.conversationID), ['live', 'snapshot']);
    logic.onClose();
  });

  test(
      'deletion rejects stale callbacks and refresh snapshots but permits a later new message',
      () async {
    final logic = ConversationLogic();
    final removed = _conversation('removed', 1);
    logic.list.add(removed);
    final refresh = logic.onRefresh();
    await _flush();
    deletion = Completer<void>();
    final deleting = logic.deleteConversation(removed);
    await _flush();
    logic.onChanged([_conversation('removed', 2)]);
    replies.single.complete(_json([_conversation('removed', 1)]));
    await refresh;
    expect(logic.list, isEmpty);
    deletion!.complete();
    await deleting;
    logic.onChanged([_conversation('removed', 2)]);
    expect(logic.list, isEmpty);
    final nextRefresh = logic.onRefresh();
    await _flush();
    replies.last.complete(_json([_conversation('removed', 1)]));
    await nextRefresh;
    expect(logic.list, isEmpty);
    logic.onChanged([_conversation('removed', 3)]);
    expect(logic.list.single.latestMsgSendTime, 3);
    logic.onClose();
  });
}
