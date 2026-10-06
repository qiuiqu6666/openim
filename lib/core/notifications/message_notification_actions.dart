import 'dart:collection';
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../pages/official_account/models/official_account.dart';
import 'message_notification_target.dart';

/// Owns native notification actions independently of any mounted chat page.
/// The app supplies SDK readiness, session validation, navigation and transport.
class MessageNotificationActions {
  MessageNotificationActions({
    required this.isCurrentSession,
    required this.isReady,
    required this.loadConversation,
    required this.openConversation,
    required this.sendReply,
    required this.cancelNotification,
    required this.reportError,
    this.maxPending = 32,
  }) : assert(maxPending > 0);

  static const openAction = 'open';
  static const replyAction = 'reply';

  final bool Function(MessageNotificationTarget target) isCurrentSession;
  final bool Function() isReady;
  final Future<ConversationInfo> Function(MessageNotificationTarget target)
      loadConversation;
  final Future<void> Function(ConversationInfo conversation) openConversation;

  /// If creation and sending each await the SDK, this callback must validate its
  /// captured session between those awaits as well as before native send.
  final Future<void> Function(String text, ConversationInfo conversation)
      sendReply;

  /// The app compares the original target with its currently displayed message
  /// before cancelling a conversation's stable native notification ID.
  final Future<void> Function(
      MessageNotificationTarget target, int notificationID) cancelNotification;
  final void Function(String message) reportError;
  final int maxPending;

  final _pending = Queue<_NotificationAction>();
  final _accepted = <String>{};
  String? _acceptedSession;
  Future<void>? _processing;
  int _generation = 0;
  bool _closed = false;

  int get pendingCount => _pending.length;

  /// Native callbacks may repeat while the SDK loads or a send is in flight.
  /// A target message ID distinguishes replies when a conversation's native
  /// notification ID is reused. Legacy payloads fall back to notification ID.
  Future<void> handle(
    String? payload, {
    String? actionId,
    String? input,
    int? notificationID,
  }) async {
    if (_closed) return;
    final target = MessageNotificationTarget.decode(payload);
    if (target == null) {
      reportError('通知内容无法识别。');
      return;
    }
    if (!isCurrentSession(target)) return;
    final action = actionId == null || actionId.isEmpty ? openAction : actionId;
    if (action != openAction && action != replyAction) {
      reportError('通知操作无法识别。');
      return;
    }
    final text = action == replyAction ? input?.trim() : null;
    if (action == replyAction && (text == null || text.isEmpty)) return;
    if (action == replyAction &&
        target.isSingleChat &&
        OfficialAccount.from(userID: target.sourceID) != null) {
      return;
    }

    final key = jsonEncode([
      target.encode(),
      action,
      if (target.messageID == null) notificationID,
      text,
    ]);
    // Active-session tombstones survive clearPending so a repeated callback
    // never retries an uncertain send. A different session releases them once.
    final session = jsonEncode([target.accountID, target.sessionKey]);
    if (_acceptedSession != session) {
      _acceptedSession = session;
      _accepted.clear();
    }
    if (_accepted.contains(key)) return;
    if (_pending.length + (_processing == null ? 0 : 1) >= maxPending) {
      reportError('通知操作暂时过多，请稍后重试。');
      return;
    }
    _accepted.add(key);
    _pending
        .add(_NotificationAction(key, target, action, text, notificationID));
    await processPending();
  }

  /// Called again after login/history synchronization makes the SDK ready.
  /// Concurrent triggers share the same drain rather than sending twice.
  Future<void> processPending() {
    if (_closed || !isReady()) return Future<void>.value();
    final current = _processing;
    if (current != null) return current;
    late final Future<void> processing;
    processing = _drain(_generation).whenComplete(() {
      if (identical(_processing, processing)) _processing = null;
    });
    _processing = processing;
    return processing;
  }

  Future<void> _drain(int generation) async {
    while (!_closed &&
        generation == _generation &&
        isReady() &&
        _pending.isNotEmpty) {
      final request = _pending.removeFirst();
      if (!_active(request.target, generation)) continue;
      var replySent = false;
      var replyStarted = false;
      var conversationOpened = false;
      try {
        final conversation = await loadConversation(request.target);
        if (!_active(request.target, generation)) continue;
        if (!request.target.matches(conversation)) {
          reportError('通知对应的聊天已失效。');
          continue;
        }
        // Readiness can change during the lookup. Preserve the accepted action
        // for the next sync-complete trigger without issuing a new SDK effect.
        if (!isReady()) {
          _pending.addFirst(request);
          return;
        }
        if (request.action == replyAction) {
          // Old native notifications may still offer reply, and role metadata
          // can become available only after a queued action loads the SDK chat.
          if (conversation.conversationType == ConversationType.single &&
              OfficialAccount.from(
                      userID: conversation.userID, ex: conversation.ex) !=
                  null) {
            continue;
          }
          replyStarted = true;
          await sendReply(request.text!, conversation);
          replySent = true;
          if (!_active(request.target, generation)) continue;
        } else {
          await openConversation(conversation);
          conversationOpened = true;
          if (!_active(request.target, generation)) continue;
        }
        if (request.notificationID != null) {
          await cancelNotification(request.target, request.notificationID!);
          if (!_active(request.target, generation)) continue;
        }
      } catch (_) {
        if (!_active(request.target, generation)) continue;
        // A failed lookup/navigation can be retried. Once send has begun its
        // outcome may be unknown, so native redelivery must not send again.
        if (!replyStarted) _accepted.remove(request.key);
        reportError(request.action == openAction
            ? conversationOpened
                ? '聊天已打开，但通知未能移除。'
                : '无法打开对应聊天，请重试。'
            : replySent
                ? '回复已发送，但通知未能移除。'
                : '回复发送失败，请打开聊天查看发送状态。');
      }
    }
  }

  bool _active(MessageNotificationTarget target, int generation) =>
      !_closed && generation == _generation && isCurrentSession(target);

  /// Cancels queued work and invalidates continuations already awaiting SDK IO.
  void clearPending() {
    _generation++;
    _pending.clear();
    _processing = null;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    clearPending();
    _accepted.clear();
    _acceptedSession = null;
  }
}

class _NotificationAction {
  const _NotificationAction(
      this.key, this.target, this.action, this.text, this.notificationID);

  final String key;
  final MessageNotificationTarget target;
  final String action;
  final String? text;
  final int? notificationID;
}
