import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/conversation_reads/conversation_read_request.dart';
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

ConversationInfo _row({
  String id = 'chat',
  String message = 'viewed',
  int unread = 3,
  int sequence = 10,
  int time = 100,
}) =>
    ConversationInfo(
      conversationID: id,
      userID: id,
      unreadCount: unread,
      latestMsgSendTime: time,
      draftTextTime: 0,
      latestMsg: Message(clientMsgID: message, seq: sequence, sendTime: time),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late ConversationLogic logic;
  late _Home home;
  late bool closed;
  late List<MethodCall> sdkCalls;
  late Completer<String> snapshot;

  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
    home = _Home();
    Get.put<HomeLogic>(home);
    logic = ConversationLogic();
    closed = false;
    sdkCalls = [];
    snapshot = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      sdkCalls.add(call);
      expect(call.method, 'getConversationListSplit');
      return snapshot.future;
    });
  });

  tearDown(() {
    if (!closed) logic.onClose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
    OpenIM.iMManager.userID = 'self';
  });

  Future<void> acknowledge(ConversationInfo row) async {
    final request = ConversationReadRequest.capture(row);
    final projecting = logic.onConversationReadRequested(request);
    request.complete(true);
    await projecting;
  }

  test('SDK success clears the matching row even without a changed event',
      () async {
    final target = _row();
    final unrelated = _row(id: 'other', unread: 7);
    logic.list.addAll([target, unrelated]);
    var updates = 0;
    final subscription = logic.list.listen((_) => updates++);
    await acknowledge(target);
    await Future<void>.delayed(Duration.zero);
    expect(target.unreadCount, 0);
    expect(unrelated.unreadCount, 7);
    expect(updates, 1);
    expect(sdkCalls, isEmpty,
        reason: 'Projection must not send a duplicate native read request.');
    await subscription.cancel();
  });

  test('request captures primitives before the SDK model advances', () async {
    final target = _row();
    final request = ConversationReadRequest.capture(target);
    target.latestMsgSendTime = 101;
    target.latestMsg!.clientMsgID = 'later';
    target.latestMsg!.seq = 11;
    target.unreadCount = 4;
    expect(request.latestMsgSendTime, 100);
    expect(request.messageID, 'viewed');
    expect(request.messageSequence, 10);
    expect(request.unreadCount, 3);
    request.complete(false);
    request.complete(true);
    expect(await request.result, isFalse);
  });

  test('SDK failure leaves the row and later same-target event unread',
      () async {
    final target = _row();
    logic.list.add(target);
    final request = ConversationReadRequest.capture(target);
    final projecting = logic.onConversationReadRequested(request);
    request.complete(false);
    await projecting;
    expect(target.unreadCount, 3);
    final incoming = _row();
    logic.onChanged([incoming]);
    expect(logic.list.single, same(incoming));
    expect(incoming.unreadCount, 3);
  });

  for (final newer in ['ID', 'sequence', 'time', 'count']) {
    test('newer $newer while native read is pending stays unread', () async {
      final target = _row();
      logic.list.add(target);
      final request = ConversationReadRequest.capture(target);
      final projecting = logic.onConversationReadRequested(request);
      final incoming = _row(
        message: newer == 'ID' ? 'unviewed' : 'viewed',
        sequence: newer == 'sequence' ? 11 : 10,
        time: newer == 'time' ? 101 : 100,
        unread: newer == 'count' ? 4 : 3,
      );
      logic.onChanged([incoming]);
      request.complete(true);
      await projecting;
      expect(logic.list.single, same(incoming));
      expect(incoming.unreadCount, newer == 'count' ? 4 : 3);
    });
  }

  test('a delayed same-target changed event cannot restore the badge',
      () async {
    final target = _row();
    logic.list.add(target);
    await acknowledge(target);
    final delayed = _row(unread: 2);
    logic.onChanged([delayed]);
    expect(logic.list.single.latestMsg!.clientMsgID, 'viewed');
    expect(logic.list.single.unreadCount, 0);
    final increased = _row(unread: 4);
    logic.onChanged([increased]);
    expect(logic.list.single, same(increased));
    expect(increased.unreadCount, 4);
    logic.onChanged([_row(unread: 2)]);
    expect(logic.list.single, same(increased));
    expect(increased.unreadCount, 4);
  });

  test('repeated confirmation does not weaken an earlier confirmed count',
      () async {
    final target = _row();
    logic.list.add(target);
    await acknowledge(target);
    await acknowledge(target);
    logic.onChanged([_row()]);
    expect(logic.list.single.unreadCount, 0);
  });

  test('painted zero-sequence target follows its unchanged same-time preview',
      () async {
    final preview =
        _row(message: 'preview-a', sequence: 30, time: 30, unread: 0);
    final painted =
        _row(message: 'painted-b', sequence: 0, time: 30, unread: 1);
    logic.list.add(preview);
    final request = ConversationReadRequest.capture(preview,
        visibleLatestMessage: painted.latestMsg, knownUnreadCount: 1);
    final projecting = logic.onConversationReadRequested(request);
    request.complete(true);
    await projecting;
    expect(request.messageID, 'painted-b');
    expect(request.messageSequence, 0);
    expect(request.latestMsgSendTime, 30);
    expect(request.unreadCount, 1);
    expect(request.followsPreview(preview), isTrue);
    logic.onChanged([painted]);
    expect(logic.list.single, same(painted));
    expect(painted.unreadCount, 0);
  });

  for (final change in ['new ID', 'increased count', 'advanced seq', 'time']) {
    test('painted target does not cover a changed preview: $change', () async {
      final preview =
          _row(message: 'preview-a', sequence: 30, time: 30, unread: 0);
      final painted =
          _row(message: 'painted-b', sequence: 0, time: 30, unread: 1);
      logic.list.add(preview);
      final request = ConversationReadRequest.capture(preview,
          visibleLatestMessage: painted.latestMsg, knownUnreadCount: 1);
      final projecting = logic.onConversationReadRequested(request);
      final changed = _row(
        message: change == 'new ID' ? 'unviewed-c' : 'preview-a',
        sequence: change == 'new ID'
            ? 0
            : change == 'advanced seq'
                ? 31
                : 30,
        time: change == 'time' ? 31 : 30,
        unread: change == 'new ID' || change == 'increased count' ? 1 : 0,
      );
      logic.onChanged([changed]);
      request.complete(true);
      await projecting;
      expect(request.followsPreview(changed), isFalse);
      logic.onChanged([painted]);
      expect(logic.list.single, same(changed));
      expect(changed.unreadCount,
          change == 'new ID' || change == 'increased count' ? 1 : 0);
    });
  }

  test('old exact preview cannot replace its confirmed painted successor',
      () async {
    final preview =
        _row(message: 'preview-a', sequence: 30, time: 30, unread: 0);
    final painted =
        _row(message: 'painted-b', sequence: 0, time: 30, unread: 1);
    logic.list.add(preview);
    final request = ConversationReadRequest.capture(preview,
        visibleLatestMessage: painted.latestMsg, knownUnreadCount: 1);
    final projecting = logic.onConversationReadRequested(request);
    request.complete(true);
    await projecting;
    logic.onChanged([painted]);
    final delayed =
        _row(message: 'preview-a', sequence: 30, time: 30, unread: 0);
    logic.onChanged([delayed]);
    expect(logic.list.single, same(painted));
    expect(painted.unreadCount, 0);
  });

  test('same-count confirmation retains the known preceding preview', () async {
    final preview =
        _row(message: 'preview-a', sequence: 30, time: 30, unread: 0);
    final painted =
        _row(message: 'painted-b', sequence: 0, time: 30, unread: 1);
    logic.list.add(preview);
    final request = ConversationReadRequest.capture(preview,
        visibleLatestMessage: painted.latestMsg, knownUnreadCount: 1);
    final projecting = logic.onConversationReadRequested(request);
    request.complete(true);
    await projecting;
    logic.onChanged([painted]);
    await acknowledge(
        _row(message: 'painted-b', sequence: 0, time: 30, unread: 1));
    logic.onChanged(
        [_row(message: 'preview-a', sequence: 30, time: 30, unread: 0)]);
    expect(logic.list.single, same(painted));
    expect(painted.unreadCount, 0);
  });

  test('painted request snapshots both target and preceding SDK preview',
      () async {
    final preview =
        _row(message: 'preview-a', sequence: 30, time: 30, unread: 2);
    final painted =
        _row(message: 'painted-b', sequence: 0, time: 30, unread: 1);
    final request = ConversationReadRequest.capture(preview,
        visibleLatestMessage: painted.latestMsg, knownUnreadCount: 1);
    preview.latestMsg!.clientMsgID = 'changed-preview';
    preview.latestMsg!.seq = 31;
    preview.latestMsgSendTime = 31;
    preview.unreadCount = 3;
    painted.latestMsg!.clientMsgID = 'changed-target';
    painted.latestMsg!.seq = 32;
    painted.latestMsg!.sendTime = 32;
    expect(request.messageID, 'painted-b');
    expect(request.messageSequence, 0);
    expect(request.latestMsgSendTime, 30);
    expect(request.unreadCount, 2,
        reason: 'Captured SDK count remains the upper bound when larger.');
    expect(
        request.followsPreview(
            _row(message: 'preview-a', sequence: 30, time: 30, unread: 2)),
        isTrue);
    expect(request.followsPreview(preview), isFalse);
    request.complete(false);
    expect(await request.result, isFalse);
  });

  for (final sequence in [0, 10]) {
    test('old confirmed callback cannot hide newer same-time ID, seq=$sequence',
        () async {
      final target = _row(sequence: sequence);
      logic.list.add(target);
      await acknowledge(target);
      final unviewed = _row(
          message: 'unviewed', sequence: sequence == 0 ? 0 : 11, unread: 1);
      logic.onChanged([unviewed]);
      logic.onChanged([_row(sequence: sequence)]);
      expect(logic.list.single, same(unviewed));
      expect(unviewed.unreadCount, 1);
    });
  }

  for (final boundary in ['close', 'account', 'clear']) {
    test('success after $boundary cannot modify the replacement list',
        () async {
      final target = _row();
      logic.list.add(target);
      final request = ConversationReadRequest.capture(target);
      final projecting = logic.onConversationReadRequested(request);
      switch (boundary) {
        case 'close':
          logic.onClose();
          closed = true;
        case 'account':
          OpenIM.iMManager.userID = 'replacement';
        case 'clear':
          logic.clearConversations();
      }
      final replacement = _row(unread: 8);
      if (boundary != 'close') logic.list.assignAll([replacement]);
      request.complete(true);
      await projecting;
      expect(target.unreadCount, 3);
      expect(replacement.unreadCount, 8);
      if (boundary == 'close') expect(logic.list, isEmpty);
    });
  }

  test('clear removes an already confirmed target guard', () async {
    final target = _row();
    logic.list.add(target);
    await acknowledge(target);
    logic.clearConversations();
    final incoming = _row();
    logic.onChanged([incoming]);
    expect(incoming.unreadCount, 3);
  });

  test('SDK refresh cannot reintroduce a confirmed target unread count',
      () async {
    final target = _row();
    logic.list.add(target);
    await acknowledge(target);
    final refreshing = logic.onRefresh();
    await Future<void>.delayed(Duration.zero);
    snapshot.complete(jsonEncode([_row().toJson()]));
    await refreshing;
    expect(logic.list.single.unreadCount, 0);
  });

  test('first-page seed uses the same confirmed target projection', () async {
    final target = _row();
    logic.list.add(target);
    await acknowledge(target);
    home.conversationsAtFirstPage.add(_row());
    await logic.getFirstPage();
    expect(logic.list.single.unreadCount, 0);
    expect(sdkCalls, isEmpty);
  });

  test('first-page seed cannot hide a newer unviewed message', () async {
    final target = _row();
    logic.list.add(target);
    await acknowledge(target);
    final later = _row(message: 'unviewed', sequence: 11, unread: 1);
    logic.onChanged([later]);
    home.conversationsAtFirstPage.add(_row());
    await logic.getFirstPage();
    expect(logic.list.single, same(later));
    expect(later.unreadCount, 1);
  });

  test('page initialization subscribes the real IM read subject', () async {
    final target = _row();
    home.conversationsAtFirstPage.add(target);
    logic.onInit();
    final request = ConversationReadRequest.capture(target);
    Get.find<IMController>().conversationReadRequestSubject.add(request);
    request.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(logic.list.single.unreadCount, 0);
    expect(sdkCalls, isEmpty);
  });

  test('subject delivery captures clear generation before native completion',
      () async {
    final target = _row();
    home.conversationsAtFirstPage.add(target);
    logic.onInit();
    final request = ConversationReadRequest.capture(target);
    Get.find<IMController>().conversationReadRequestSubject.add(request);
    logic.clearConversations();
    final replacement = _row();
    logic.list.add(replacement);
    request.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(logic.list.single, same(replacement));
    expect(replacement.unreadCount, 3);
  });
}
