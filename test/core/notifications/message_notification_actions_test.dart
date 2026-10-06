import 'dart:async';
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/message_notification_actions.dart';
import 'package:openim/core/notifications/message_notification_target.dart';

void main() {
  group('MessageNotificationTarget', () {
    for (final type in [
      ConversationType.single,
      2,
      ConversationType.superGroup
    ]) {
      test('round trips SDK conversation type $type and matches its source',
          () {
        final original = _target(type: type);
        final decoded = MessageNotificationTarget.decode(original.encode())!;
        expect(decoded.accountID, original.accountID);
        expect(decoded.sessionKey, original.sessionKey);
        expect(decoded.conversationID, original.conversationID);
        expect(decoded.sourceID, original.sourceID);
        expect(decoded.sessionType, type);
        expect(decoded.matches(_conversation(decoded)), isTrue);
      });
    }

    test('rejects malformed, missing, extra and incorrectly typed fields', () {
      final data = jsonDecode(_target().encode()) as Map<String, dynamic>;
      final invalid = <String?>[
        null,
        '',
        '{',
        '[]',
        'null',
        jsonEncode({...data, 'version': 2}),
        jsonEncode({...data, 'version': 1.0}),
        jsonEncode({...data, 'sessionType': '1'}),
        jsonEncode({...data, 'sessionType': ConversationType.notification}),
        jsonEncode({...data, 'sessionType': 0}),
        jsonEncode({...data, 'accountID': null}),
        jsonEncode({...data, 'sessionKey': ''}),
        jsonEncode({...data, 'sourceID': ' peer '}),
        jsonEncode({...data, 'conversationID': '   '}),
        jsonEncode({...data, 'extra': true}),
        jsonEncode({...data}..remove('sourceID')),
        ' ' * 8193,
      ];
      for (final payload in invalid) {
        expect(MessageNotificationTarget.decode(payload), isNull);
      }
      expect(_target(type: ConversationType.notification).encode,
          throwsArgumentError);
    });

    test('SDK conversation ID, type and destination must all match', () {
      final single = _target();
      final group = _target(type: ConversationType.superGroup);
      final wrong = [
        _conversation(single)..conversationID = 'different',
        _conversation(single)..conversationType = ConversationType.superGroup,
        _conversation(single)..userID = 'different',
        _conversation(single)..groupID = 'another-group',
      ];
      for (final conversation in wrong) {
        expect(single.matches(conversation), isFalse);
      }
      expect(
          group.matches(_conversation(group)..groupID = 'different'), isFalse);
      expect(group.matches(_conversation(group)..userID = 'another-peer'),
          isFalse);
      expect(
          group.matches(_conversation(group)..conversationType = 2), isFalse);
    });
  });

  test('message identity is strict and legacy version one remains readable',
      () {
    expect(MessageNotificationTarget.decode(_target().encode())!.messageID,
        isNull);
    final current = _target(messageID: 'new-message');
    expect(MessageNotificationTarget.decode(current.encode())!.messageID,
        'new-message');
    final data = jsonDecode(current.encode()) as Map<String, dynamic>;
    for (final invalid in [null, '', ' msg ', 42]) {
      expect(
          MessageNotificationTarget.decode(
              jsonEncode({...data, 'messageID': invalid})),
          isNull);
    }
  });

  group('MessageNotificationActions', () {
    test(
        'known notification accounts ignore stale reply but allow opening chat',
        () async {
      for (final id in ['99Message', '99Pay']) {
        final h = _Harness()..ready = false;
        final target = _target(sourceID: id);
        await h.reply(target: target);
        expect(h.actions.pendingCount, 0);
        expect(h.lookups, 0);
        h.ready = true;
        await h.actions.handle(target.encode(), notificationID: 7);
        expect(h.sent, isEmpty);
        expect(h.opened, ['conversation']);
        expect(h.cancelled, [7]);
        expect(h.errors, isEmpty);
      }
    });

    test(
        'queued replies are discarded when SDK metadata resolves notification role',
        () async {
      final h = _Harness()..ready = false;
      h.lookup = (target) async => _conversation(target)
        ..ex = '{"accountType":"official","officialRole":"message"}';
      await h.reply();
      expect(h.actions.pendingCount, 1);
      h.ready = true;
      await h.actions.processPending();
      await h.reply();
      expect(h.actions.pendingCount, 0);
      expect(h.sent, isEmpty);
      expect(h.cancelled, isEmpty);
      expect(h.lookups, 1, reason: 'A duplicate discarded reply is ignored');
      await h.actions.handle(_target().encode(), notificationID: 7);
      expect(h.opened, ['conversation']);
      expect(h.cancelled, [7]);
      expect(h.errors, isEmpty);
    });

    test('notification account IDs in a group destination retain reply',
        () async {
      final h = _Harness();
      await h.reply(
          target:
              _target(sourceID: '99Pay', type: ConversationType.superGroup));
      expect(h.sent, ['reply']);
      expect(h.destinations.single.groupID, '99Pay');
      expect(h.cancelled, [7]);
    });

    test('body tap and explicit open use SDK conversation data', () async {
      final h = _Harness();
      await h.actions.handle(_target().encode(), notificationID: 1);
      await h.actions.handle(_target().encode(),
          actionId: MessageNotificationActions.openAction, notificationID: 2);
      expect(h.opened, ['conversation', 'conversation']);
      expect(h.sent, isEmpty);
      expect(h.cancelled, [1, 2]);
      expect(h.errors, isEmpty);
    });

    test('reply uses native input without opening chat and cancels on success',
        () async {
      final h = _Harness();
      await h.reply(text: '  native reply\n  ');
      expect(h.sent, ['native reply']);
      expect(h.opened, isEmpty);
      expect(h.cancelled, [7]);
      expect(h.errors, isEmpty);
    });

    test('legacy and supergroup replies resolve group rather than user',
        () async {
      final h = _Harness();
      for (final type in [2, ConversationType.superGroup]) {
        await h.reply(target: _target(type: type));
      }
      expect(h.destinations.every((c) => c.groupID == 'peer'), isTrue);
      expect(h.destinations.every((c) => c.userID == null), isTrue);
      expect(h.sent, hasLength(2));
    });

    test('missing and whitespace replies do not query, send or cancel',
        () async {
      final h = _Harness();
      for (final text in <String?>[null, '', ' \n\t']) {
        await h.reply(text: text);
      }
      expect(h.lookups, 0);
      expect(h.sent, isEmpty);
      expect(h.cancelled, isEmpty);
    });

    test('malformed payload and unknown action report without SDK effects',
        () async {
      final h = _Harness();
      await h.actions.handle('bad json');
      await h.actions.handle(_target().encode(), actionId: 'unexpected');
      expect(h.errors, hasLength(2));
      expect(h.lookups, 0);
    });

    test('old account and renewed token payloads are ignored', () async {
      final h = _Harness();
      h.accountID = 'another-account';
      await h.reply();
      h.accountID = 'owner';
      h.sessionKey = 'renewed-session';
      await h.reply();
      expect(h.lookups, 0);
      expect(h.errors, isEmpty);
    });

    test('SDK mismatch retains notification and does not navigate or send',
        () async {
      final h = _Harness();
      h.lookup = (target) async => _conversation(target)..userID = 'wrong-peer';
      await h.reply();
      await h.actions.handle(_target().encode(), notificationID: 8);
      expect(h.sent, isEmpty);
      expect(h.opened, isEmpty);
      expect(h.cancelled, isEmpty);
      expect(h.errors, hasLength(2));
    });

    test('not-ready actions queue in order and drain once after sync',
        () async {
      final h = _Harness()..ready = false;
      await h.actions.handle(_target().encode(), notificationID: 1);
      await h.reply(text: 'first', id: 2);
      await h.reply(text: 'second', id: 3);
      await h.reply(text: 'first', id: 2);
      await h.actions.processPending();
      expect(h.actions.pendingCount, 3);
      expect(h.lookups, 0);
      h.ready = true;
      await Future.wait(
          [h.actions.processPending(), h.actions.processPending()]);
      expect(h.effects, ['open:conversation', 'reply:first', 'reply:second']);
      expect(h.cancelled, [1, 2, 3]);
      expect(h.actions.pendingCount, 0);
    });

    test('bounded queue rejects overflow and later accepts that callback',
        () async {
      final h = _Harness(maxPending: 2)..ready = false;
      await h.reply(id: 1);
      await h.reply(id: 2);
      await h.reply(id: 3);
      expect(h.actions.pendingCount, 2);
      expect(h.errors, hasLength(1));
      h.ready = true;
      await h.actions.processPending();
      await h.reply(id: 3);
      expect(h.cancelled, [1, 2, 3]);
    });

    test('duplicates during lookup, send and after receipt cannot send twice',
        () async {
      final h = _Harness();
      final lookup = Completer<ConversationInfo>();
      final sent = Completer<void>();
      h.lookup = (_) => lookup.future;
      h.onSend = (_, __) => sent.future;
      final first = h.reply();
      await h.reply();
      expect(h.lookups, 1);
      lookup.complete(_conversation(_target()));
      await h.sendStarted.future;
      await h.reply();
      expect(h.sent, ['reply']);
      sent.complete();
      await first;
      await h.reply();
      expect(h.sent, ['reply']);
      expect(h.cancelled, [7]);
    });

    test('same reply on distinct notifications remains a distinct action',
        () async {
      final h = _Harness();
      await h.reply(id: 1);
      await h.reply(id: 2);
      expect(h.sent, ['reply', 'reply']);
      expect(h.cancelled, [1, 2]);
    });

    test('replacement notification permits same text for a new message only',
        () async {
      final h = _Harness();
      final first = _target(messageID: 'message-1');
      final second = _target(messageID: 'message-2');
      await h.reply(text: '好', target: first);
      await h.reply(text: ' 好 ', target: first);
      await h.reply(text: '好', target: second);
      await h.reply(text: '好', target: second);
      expect(h.sent, ['好', '好']);
      expect(h.cancelled, [7, 7]);
    });

    test('native callback ID variations cannot duplicate an identified reply',
        () async {
      final h = _Harness();
      final target = _target(messageID: 'message-1');
      await h.reply(id: null, target: target);
      await h.reply(id: 7, target: target);
      await h.reply(id: 8, target: target);
      expect(h.sent, ['reply']);
      expect(h.lookups, 1);
    });

    test('readiness lost during lookup defers transport until next sync',
        () async {
      final h = _Harness();
      final lookup = Completer<ConversationInfo>();
      h.lookup = (_) => lookup.future;
      final first = h.reply();
      h.ready = false;
      lookup.complete(_conversation(_target()));
      await first;
      expect(h.sent, isEmpty);
      expect(h.actions.pendingCount, 1);
      h.lookup = null;
      h.ready = true;
      await h.actions.processPending();
      expect(h.sent, ['reply']);
      expect(h.cancelled, [7]);
    });

    for (final change in ['account', 'token', 'close', 'clear']) {
      test('$change during lookup prevents late navigation and reply',
          () async {
        final h = _Harness();
        final lookup = Completer<ConversationInfo>();
        h.lookup = (_) => lookup.future;
        final first = h.reply();
        final queuedOpen =
            h.actions.handle(_target().encode(), notificationID: 9);
        switch (change) {
          case 'account':
            h.accountID = 'other';
          case 'token':
            h.sessionKey = 'other';
          case 'close':
            h.actions.close();
          case 'clear':
            h.actions.clearPending();
        }
        lookup.complete(_conversation(_target()));
        await Future.wait([first, queuedOpen]);
        expect(h.sent, isEmpty);
        expect(h.opened, isEmpty);
        expect(h.cancelled, isEmpty);
        expect(h.errors, isEmpty);
      });
    }

    test(
        'token changes after sending prevent cancelling the new session notification',
        () async {
      final h = _Harness();
      final sent = Completer<void>();
      h.onSend = (_, __) => sent.future;
      final first = h.reply();
      await h.sendStarted.future;
      h.sessionKey = 'renewed-session';
      sent.complete();
      await first;
      expect(h.sent, ['reply']);
      expect(h.cancelled, isEmpty);
      expect(h.errors, isEmpty);
    });

    test(
        'clearPending cancels queued actions and ignores duplicate old callbacks',
        () async {
      final h = _Harness()..ready = false;
      await h.reply();
      h.actions.clearPending();
      h.ready = true;
      await h.actions.processPending();
      await h.reply();
      expect(h.actions.pendingCount, 0);
      expect(h.sent, isEmpty);
    });

    test('new generation need not wait for an abandoned SDK lookup', () async {
      final h = _Harness();
      final oldLookup = Completer<ConversationInfo>();
      h.lookup = (_) => oldLookup.future;
      final old = h.reply(id: 1);
      h.actions.clearPending();
      h.lookup = null;
      await h.reply(id: 2);
      expect(h.cancelled, [2]);
      oldLookup.complete(_conversation(_target()));
      await old;
      expect(h.sent, ['reply']);
    });

    test('lookup failure permits retry without dismissing the notification',
        () async {
      final h = _Harness();
      h.lookup = (_) async => throw StateError('lookup failed');
      await h.reply();
      expect(h.errors, hasLength(1));
      expect(h.cancelled, isEmpty);
      h.lookup = null;
      await h.reply();
      expect(h.sent, ['reply']);
      expect(h.cancelled, [7]);
    });

    test(
        'uncertain send failure retains notification and cannot be resent by redelivery',
        () async {
      final h = _Harness();
      h.onSend = (_, __) async => throw TimeoutException('unknown receipt');
      await h.reply();
      await h.reply();
      expect(h.sent, ['reply']);
      expect(h.cancelled, isEmpty);
      expect(h.errors, hasLength(1));
    });

    test('cancel failure reports sent state without retrying the reply',
        () async {
      final h = _Harness();
      h.onCancel = (_) async => throw StateError('native cancel failed');
      await h.reply();
      await h.reply();
      expect(h.sent, ['reply']);
      expect(h.errors.single, contains('回复已发送'));
    });

    test('token change during native cancel ignores its late failure',
        () async {
      final h = _Harness();
      final cancel = Completer<void>();
      final cancelStarted = Completer<void>();
      h.onCancel = (_) {
        cancelStarted.complete();
        return cancel.future;
      };
      final first = h.reply();
      await cancelStarted.future;
      h.sessionKey = 'renewed-session';
      cancel.completeError(StateError('old platform result'));
      await first;
      expect(h.sent, ['reply']);
      expect(h.errors, isEmpty);
    });

    test('navigation failure keeps notification and allows a later tap',
        () async {
      final h = _Harness();
      h.onOpen = (_) async => throw StateError('route failed');
      await h.actions.handle(_target().encode(), notificationID: 1);
      h.onOpen = null;
      await h.actions.handle(_target().encode(), notificationID: 1);
      expect(h.opened, ['conversation', 'conversation']);
      expect(h.cancelled, [1]);
      expect(h.errors, hasLength(1));
    });

    test('close is idempotent and rejects future actions and drain triggers',
        () async {
      final h = _Harness()..ready = false;
      await h.reply();
      h.actions.close();
      h.actions.close();
      h.ready = true;
      await h.actions.processPending();
      await h.reply(id: 9);
      expect(h.actions.pendingCount, 0);
      expect(h.lookups, 0);
    });
  });
}

MessageNotificationTarget _target({
  int type = ConversationType.single,
  String? messageID,
  String sourceID = 'peer',
}) =>
    MessageNotificationTarget(
      accountID: 'owner',
      sessionKey: 'session-fingerprint',
      conversationID: 'conversation',
      sourceID: sourceID,
      sessionType: type,
      messageID: messageID,
    );

ConversationInfo _conversation(MessageNotificationTarget target) =>
    ConversationInfo(
      conversationID: target.conversationID,
      conversationType: target.sessionType,
      userID: target.isSingleChat ? target.sourceID : null,
      groupID: target.isSingleChat ? null : target.sourceID,
      showName: 'SDK name',
    );

class _Harness {
  _Harness({int maxPending = 32}) {
    actions = MessageNotificationActions(
      isCurrentSession: (target) =>
          target.accountID == accountID && target.sessionKey == sessionKey,
      isReady: () => ready,
      loadConversation: (target) {
        lookups++;
        return lookup?.call(target) ?? Future.value(_conversation(target));
      },
      openConversation: (conversation) async {
        opened.add(conversation.conversationID);
        effects.add('open:${conversation.conversationID}');
        await onOpen?.call(conversation);
      },
      sendReply: (text, conversation) async {
        sent.add(text);
        destinations.add(conversation);
        effects.add('reply:$text');
        if (!sendStarted.isCompleted) sendStarted.complete();
        await onSend?.call(text, conversation);
      },
      cancelNotification: (target, id) async {
        cancelled.add(id);
        cancelledTargets.add(target);
        await onCancel?.call(id);
      },
      reportError: errors.add,
      maxPending: maxPending,
    );
  }

  late final MessageNotificationActions actions;
  bool ready = true;
  String accountID = 'owner';
  String sessionKey = 'session-fingerprint';
  int lookups = 0;
  final sendStarted = Completer<void>();
  final opened = <String>[];
  final sent = <String>[];
  final cancelled = <int>[];
  final cancelledTargets = <MessageNotificationTarget>[];
  final errors = <String>[];
  final effects = <String>[];
  final destinations = <ConversationInfo>[];
  Future<ConversationInfo> Function(MessageNotificationTarget)? lookup;
  Future<void> Function(String, ConversationInfo)? onSend;
  Future<void> Function(ConversationInfo)? onOpen;
  Future<void> Function(int)? onCancel;

  Future<void> reply({
    String? text = 'reply',
    int? id = 7,
    MessageNotificationTarget? target,
  }) =>
      actions.handle(
        (target ?? _target()).encode(),
        actionId: MessageNotificationActions.replyAction,
        input: text,
        notificationID: id,
      );
}
