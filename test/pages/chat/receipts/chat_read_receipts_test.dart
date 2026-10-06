import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/conversation_reads/conversation_read_request.dart';
import 'package:openim/pages/chat/receipts/chat_read_receipts.dart';

class _ReadCall {
  _ReadCall(this.method, this.arguments);
  final String method;
  final Map<String, dynamic> arguments;
  final result = Completer<void>();
}

Message _received(String id, int sequence) => Message(
    clientMsgID: id,
    contentType: MessageType.text,
    sendID: 'peer',
    seq: sequence,
    isRead: false);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late ChatReadReceipts receipts;
  late RxList<Message> messages;
  late List<_ReadCall> calls;
  late ConversationInfo conversation;
  late List<ConversationReadRequest> projections;
  late bool active;
  late bool canReadConversation;

  setUp(() {
    OpenIM.iMManager.userID = 'self';
    calls = [];
    messages = <Message>[].obs;
    conversation = ConversationInfo(conversationID: 'chat');
    projections = [];
    active = true;
    canReadConversation = true;
    receipts = ChatReadReceipts(
      messageList: messages,
      conversation: () => conversation,
      // The route supplies one session boundary to all extracted modules.
      isClosed: () => OpenIM.iMManager.userID != 'self',
      isActive: () => active,
      canReadConversation: () => canReadConversation,
      isSessionActive: () => OpenIM.iMManager.userID == 'self',
      onConversationRead: projections.add,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, (call) async {
      final read = _ReadCall(
          call.method, Map<String, dynamic>.from(call.arguments as Map));
      calls.add(read);
      return read.result.future;
    });
  });
  tearDown(() {
    receipts.close();
    for (final call in calls) {
      if (!call.result.isCompleted) call.result.complete();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
  });

  test('visible messages share one conversation read request', () async {
    final first = _received('first', 1);
    final second = _received('second', 2);
    messages.addAll([first, second]);
    final readingFirst = receipts.markRead(first);
    final readingSecond = receipts.markRead(second);
    await _flush();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'markConversationMessageAsRead');
    calls.single.result.complete();
    await Future.wait([readingFirst, readingSecond]);
    expect(first.isRead, isTrue);
    expect(second.isRead, isTrue);
  });

  test('visible latest cannot consume an earlier entering row, even at close',
      () async {
    final entering = _received('entering', 10);
    final latest = _received('immediate-self-latest', 11)..sendID = 'self';
    messages.addAll([entering, latest]);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 1, latestMsg: latest);
    canReadConversation = false;

    // Only the nonanimated latest row is fully painted. A whole-conversation
    // request would still consume the preceding incoming row underneath it.
    await receipts.markVisibleMessages(['immediate-self-latest']);
    receipts.conversationChanged();
    receipts.clearUnreadCount();
    active = false;
    receipts.clearUnreadCount(leaving: true);
    await _flush();
    expect(calls, isEmpty);
    expect(projections, isEmpty);
    expect(entering.isRead, isFalse);

    canReadConversation = true;
    receipts.clearUnreadCount(leaving: true);
    await _flush();
    expect(calls, isEmpty,
        reason:
            'Finishing under a covered route cannot validate a blocked view.');
    active = true;
    final painted =
        receipts.markVisibleMessages(['entering', 'immediate-self-latest']);
    await _flush();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'markConversationMessageAsRead');
    expect(projections.single.messageID, 'immediate-self-latest');
    calls.single.result.complete();
    await painted;
    expect(entering.isRead, isTrue);
    expect(await projections.single.result, isTrue);
  });

  test('ordinary explicit reads cannot bypass the entrance barrier', () async {
    final message = _received('ordinary', 10);
    messages.add(message);
    canReadConversation = false;

    await receipts.markRead(message);
    receipts.markMessageAsRead(message, true);
    await _flush();
    expect(calls, isEmpty);
    expect(projections, isEmpty);
    expect(message.isRead, isFalse);
    expect(message.hasReadTime, isNull);

    canReadConversation = true;
    final retry = receipts.markRead(message);
    await _flush();
    expect(calls, hasLength(1));
    calls.single.result.complete();
    await retry;
    expect(message.isRead, isTrue);
  });

  test(
      'fully painted private ID can burn without clearing an entering neighbour',
      () async {
    final entering = _received('entering', 10);
    final private = _received('private', 11)
      ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    messages.addAll([entering, private]);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 2, latestMsg: private);
    canReadConversation = false;

    final painted = receipts.markVisibleMessages(['private']);
    await _flush();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'markMessagesAsReadByMsgID');
    expect(calls.single.arguments['messageIDList'], ['private']);
    expect(private.attachedInfoElem!.hasReadTime, isNull);
    receipts.clearUnreadCount(leaving: true);
    await _flush();
    expect(calls, hasLength(1));
    expect(projections, isEmpty);

    calls.single.result.complete();
    await painted;
    expect(private.isRead, isTrue);
    expect(private.attachedInfoElem!.hasReadTime, greaterThan(0));
    expect(entering.isRead, isFalse);
    expect(entering.hasReadTime, isNull);
  });

  test('a queued latest read rechecks the entrance barrier before native IO',
      () async {
    final first = _received('first-painted', 10);
    messages.add(first);
    final readingFirst = receipts.markVisibleMessages(['first-painted']);
    await _flush();
    expect(calls, hasLength(1));

    final latest = _received('later-painted', 11);
    messages.add(latest);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 2, latestMsg: latest);
    final readingLatest = receipts.markVisibleMessages(['later-painted']);
    await _flush();
    expect(calls, hasLength(1));

    // Another incoming row can enter while the previous request is in flight.
    // Neither the queued request nor route-close clear may bypass that barrier.
    canReadConversation = false;
    receipts.clearUnreadCount(leaving: true);
    calls.first.result.complete();
    await Future.wait([readingFirst, readingLatest]);
    await _flush();
    expect(calls, hasLength(1));
    expect(projections, hasLength(1));
    expect(latest.isRead, isFalse);

    canReadConversation = true;
    final retry = receipts.markVisibleMessages(['later-painted']);
    await _flush();
    expect(calls, hasLength(2));
    expect(projections.last.messageID, 'later-painted');
    calls.last.result.complete();
    await retry;
    expect(latest.isRead, isTrue);
  });

  test('newer message arriving during read requires a second request',
      () async {
    final first = _received('first', 10);
    messages.add(first);
    final readingFirst = receipts.markRead(first);
    await _flush();
    final second = _received('second', 11);
    messages.add(second);
    final readingSecond = receipts.markRead(second);
    calls.first.result.complete();
    await _flush();
    expect(calls, hasLength(2));
    calls.last.result.complete();
    await Future.wait([readingFirst, readingSecond]);
    expect(second.isRead, isTrue);
  });

  for (final knownSequence in [0, 10]) {
    test(
        'unsequenced arrival after pending seq $knownSequence read is not lost',
        () async {
      final first = _received('first', knownSequence);
      messages.add(first);
      final readingFirst = receipts.markRead(first);
      await _flush();
      final second = _received('without-seq', 0);
      messages.add(second);
      final readingSecond = receipts.markRead(second);
      calls.first.result.complete();
      await _flush();
      final count = calls.length;
      for (final call in calls) {
        if (!call.result.isCompleted) call.result.complete();
      }
      await Future.wait([readingFirst, readingSecond]);
      expect(count, 2);
      expect(second.isRead, isTrue);
    });
  }

  test(
      'unsequenced messages already in the same visible batch share one request',
      () async {
    final first = _received('without-seq-first', 0);
    final second = _received('without-seq-second', 0);
    messages.addAll([first, second]);
    final readingFirst = receipts.markRead(first);
    final readingSecond = receipts.markRead(second);
    await _flush();
    calls.first.result.complete();
    await _flush();
    final count = calls.length;
    for (final call in calls) {
      if (!call.result.isCompleted) call.result.complete();
    }
    await Future.wait([readingFirst, readingSecond]);
    expect(count, 1);
  });

  for (final private in [false, true]) {
    test(
        'painted ${private ? 'private' : 'ordinary'} voice clears unread without listening or burning',
        () async {
      final voice = _received('voice', 10)
        ..contentType = MessageType.voice
        ..localEx = '{"voiceHeard":false}';
      if (private) {
        voice.attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
      }
      conversation = ConversationInfo(
          conversationID: 'chat', unreadCount: 1, latestMsg: voice);
      messages.add(voice);
      final pending = receipts.markVisibleMessages(['voice']);
      await _flush();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'markConversationMessageAsRead');
      calls.single.result.complete();
      await pending;
      expect(voice.isRead, isFalse);
      expect(voice.hasReadTime, isNull);
      expect(voice.attachedInfoElem?.hasReadTime, isNull);
      expect(voice.localEx, '{"voiceHeard":false}');
      expect(await projections.single.result, isTrue);

      if (private) {
        final played = receipts.markRead(voice);
        await _flush();
        expect(calls, hasLength(2));
        expect(calls.last.method, 'markMessagesAsReadByMsgID');
        expect(calls.last.arguments['messageIDList'], ['voice']);
        expect(voice.attachedInfoElem!.hasReadTime, isNull);
        calls.last.result.complete();
        await played;
        expect(voice.isRead, isTrue);
        expect(voice.attachedInfoElem!.hasReadTime, greaterThan(0));
      }
    });
  }

  test(
      'an already locally read latest message still clears its conversation unread badge',
      () async {
    final latest = _received('latest', 10)..isRead = true;
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 2, latestMsg: latest);
    messages.add(latest);
    final pending = receipts.markVisibleMessages(['latest']);
    await _flush();
    expect(calls, hasLength(1));
    calls.single.result.complete();
    await pending;
    expect(await projections.single.result, isTrue);
  });

  test('viewport read failure can retry the same painted latest message',
      () async {
    final latest = _received('latest', 10);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 1, latestMsg: latest);
    messages.add(latest);
    final failed = receipts.markVisibleMessages(['latest']);
    await _flush();
    calls.single.result.completeError(PlatformException(code: 'SDK_FAILURE'));
    await failed;
    expect(latest.isRead, isFalse);
    expect(await projections.single.result, isFalse);
    final retry = receipts.markVisibleMessages(['latest']);
    await _flush();
    expect(calls, hasLength(2));
    calls.last.result.complete();
    await retry;
    expect(latest.isRead, isTrue);
  });

  test(
      'positive unread observation retries the same latest ID and read watermark',
      () async {
    final latest = _received('latest', 10);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 1, latestMsg: latest);
    messages.add(latest);
    final first = receipts.markVisibleMessages(['latest']);
    await _flush();
    calls.single.result.complete();
    await first;
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 1, latestMsg: latest);
    receipts.conversationChanged();
    await _flush();
    expect(calls, hasLength(2));
    calls.last.result.complete();
    await _flush();
    receipts.conversationChanged();
    await _flush();
    expect(calls, hasLength(2),
        reason: 'identical repeated SDK events coalesce');
  });

  test(
      'scrolling above latest preserves unseen conversation arrivals even at close',
      () async {
    final older = _received('older', 10);
    final latest = _received('unseen', 11);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 2, latestMsg: latest);
    messages.addAll([older, latest]);
    await receipts.markVisibleMessages(['older'], atLatest: false);
    receipts.clearUnreadCount();
    await _flush();
    expect(calls, isEmpty);
    expect(older.isRead, isFalse);
    expect(latest.isRead, isFalse);
  });

  test(
      'SDK latest announced before the timeline arrives is not cleared as seen',
      () async {
    final timelineLatest = _received('timeline-latest', 10);
    final notPainted = _received('not-yet-in-timeline', 11);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 1, latestMsg: notPainted);
    messages.add(timelineLatest);
    await receipts.markVisibleMessages(['timeline-latest']);
    receipts.conversationChanged();
    receipts.clearUnreadCount();
    await _flush();
    expect(calls, isEmpty);
    expect(timelineLatest.isRead, isFalse);
  });

  test(
      'covered chat rejects painted reads then accepts the same latest on reentry',
      () async {
    final latest = _received('latest', 10);
    messages.add(latest);
    active = false;
    await receipts.markVisibleMessages(['latest']);
    expect(calls, isEmpty);
    active = true;
    final pending = receipts.markVisibleMessages(['latest']);
    await _flush();
    expect(calls, hasLength(1));
    calls.single.result.complete();
    await pending;
    expect(latest.isRead, isTrue);
  });

  test('late visibility observer on a covered chat cannot start a private burn',
      () async {
    final private = _received('private', 10)
      ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    messages.add(private);
    active = false;
    receipts.markMessageAsRead(private, true);
    await _flush();
    final count = calls.length;
    for (final call in calls) {
      if (!call.result.isCompleted) call.result.complete();
    }
    await _flush();
    expect(count, 0);
    expect(private.attachedInfoElem!.hasReadTime, isNull);
  });

  for (final boundary in ['covered', 'scroll away']) {
    test('queued viewport read cancels after $boundary and retries on reentry',
        () async {
      final first = _received('first', 10);
      messages.add(first);
      final readingFirst = receipts.markVisibleMessages(['first']);
      await _flush();
      final second = _received('second', 11);
      messages.add(second);
      final readingSecond = receipts.markVisibleMessages(['second']);
      if (boundary == 'covered') {
        active = false;
      } else {
        await receipts.markVisibleMessages(['first'], atLatest: false);
      }
      calls.first.result.complete();
      await _flush();
      final count = calls.length;
      for (final call in calls) {
        if (!call.result.isCompleted) call.result.complete();
      }
      await Future.wait([readingFirst, readingSecond]);
      expect(count, 1);
      expect(second.isRead, isFalse);

      active = true;
      final retry = receipts.markVisibleMessages(['second']);
      await _flush();
      expect(calls, hasLength(2));
      calls.last.result.complete();
      await retry;
      expect(second.isRead, isTrue);
    });
  }

  test(
      'final seen queued target is sent before close while the previous SDK read is pending',
      () async {
    final first = _received('first', 10);
    messages.add(first);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 1, latestMsg: first);
    final readingFirst = receipts.markVisibleMessages(['first']);
    await _flush();
    final second = _received('second', 11);
    messages.add(second);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 2, latestMsg: second);
    final readingSecond = receipts.markVisibleMessages(['second']);
    await _flush();
    expect(calls, hasLength(1));
    // Navigator may have switched to the list before chat's onClose runs.
    active = false;
    receipts.clearUnreadCount(leaving: true);
    await _flush();
    expect(calls, hasLength(2));
    receipts.close();
    calls.last.result.complete();
    calls.first.result.complete();
    await Future.wait([readingFirst, readingSecond]);
    expect(calls, hasLength(2));
    expect(await projections.last.result, isTrue);
    expect(second.isRead, isFalse);
  });

  test(
      'final clear does not duplicate the same seen target already in SDK flight',
      () async {
    final latest = _received('latest', 10);
    messages.add(latest);
    conversation = ConversationInfo(
        conversationID: 'chat', unreadCount: 1, latestMsg: latest);
    final pending = receipts.markVisibleMessages(['latest']);
    await _flush();
    receipts.clearUnreadCount();
    await _flush();
    expect(calls, hasLength(1));
    receipts.close();
    calls.single.result.complete();
    await pending;
    expect(await projections.single.result, isTrue);
    expect(latest.isRead, isFalse);
  });

  test('late SDK success cannot publish read success to a replacement account',
      () async {
    final latest = _received('latest', 10);
    messages.add(latest);
    final pending = receipts.markVisibleMessages(['latest']);
    await _flush();
    OpenIM.iMManager.userID = 'another-account';
    calls.single.result.complete();
    await pending;
    expect(await projections.single.result, isFalse);
    expect(latest.isRead, isFalse);
  });

  test('private messages use ID read and start their burn time after success',
      () async {
    final message = _received('private', 1)
      ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    final pending = receipts.markRead(message);
    await _flush();
    expect(calls.single.method, 'markMessagesAsReadByMsgID');
    calls.single.result.complete();
    await pending;
    expect(message.isRead, isTrue);
    expect(message.attachedInfoElem!.hasReadTime, greaterThan(0));
  });

  test('late SDK read after close leaves local read state unchanged', () async {
    final message = _received('late', 1);
    messages.add(message);
    final pending = receipts.markRead(message);
    await _flush();
    receipts.close();
    calls.single.result.complete();
    await pending;
    expect(message.isRead, isFalse);
    expect(message.hasReadTime, isNull);
  });

  test('late SDK read after account switch leaves old route state unchanged',
      () async {
    final message = _received('late', 1);
    messages.add(message);
    final pending = receipts.markRead(message);
    await _flush();
    OpenIM.iMManager.userID = 'next-account';
    calls.single.result.complete();
    await pending;
    expect(message.isRead, isFalse);
    expect(message.hasReadTime, isNull);
  });

  test('closed receipts do not start another message read request', () async {
    receipts.close();
    final pending = receipts.markRead(_received('after-close', 1));
    await _flush();
    for (final call in calls) {
      call.result.complete();
    }
    await pending;
    expect(calls, isEmpty);
  });

  for (final boundary in ['close', 'account switch']) {
    test('queued newer read stops before native SDK after $boundary', () async {
      final first = _received('first', 10);
      messages.add(first);
      final readingFirst = receipts.markRead(first);
      await _flush();
      final second = _received('second', 11);
      messages.add(second);
      final readingSecond = receipts.markRead(second);
      if (boundary == 'close') {
        receipts.close();
      } else {
        OpenIM.iMManager.userID = 'next-account';
      }
      calls.first.result.complete();
      await _flush();
      // Finish unexpected work as well, so a failing assertion cannot leave
      // a pending native-method mock or hang the remainder of the suite.
      for (final call in calls) {
        if (!call.result.isCompleted) call.result.complete();
      }
      await Future.wait([readingFirst, readingSecond]);
      expect(calls, hasLength(1));
      expect(first.isRead, isFalse);
      expect(second.isRead, isFalse);
    });
  }

  test('C2C receipt bursts filter peers and publish one refresh', () async {
    final matching = _received('matching', 1);
    final unrelated = _received('unrelated', 2);
    messages.addAll([matching, unrelated]);
    var refreshes = 0;
    final subscription = messages.listen((_) => refreshes++);
    for (var i = 0; i < 50; i++) {
      receipts.applyC2CReceipt([
        ReadReceiptInfo(userID: 'peer', msgIDList: ['matching']),
        ReadReceiptInfo(userID: 'other-peer', msgIDList: ['unrelated']),
      ], 'peer');
    }
    await _flush();
    expect(matching.isRead, isTrue);
    expect(unrelated.isRead, isFalse);
    expect(refreshes, 1);
    await subscription.cancel();
  });
}
