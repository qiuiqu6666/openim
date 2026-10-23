import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/chat_history_cache.dart';
import '../../../../services/chat_revocation_notice.dart';
import '../../../../services/chat_message_sender.dart';
import '../../../../services/favorite_send_coordinator.dart';
import '../../../../services/messaging/message_send_session.dart';
import '../diagnostics/chat_media_diagnostics.dart';
import 'chat_media_upload.dart';

/// Process-local owner of accepted media. A route only observes these tasks.
class ChatMediaOutbox {
  ChatMediaOutbox(
      {ChatMessageSender? sender,
      this.confirmTimeout = const Duration(seconds: 30)})
      : _sender = sender ?? ChatMessageSender();
  static final instance = ChatMediaOutbox();
  final ChatMessageSender _sender;
  final Duration confirmTimeout;
  final _entries = <String, MediaOutboxEntry>{};
  int _generation = 0;
  bool _observingRoutes = false;
  void clear() {
    if (_observingRoutes) {
      Config.networkRouteRevision.removeListener(_routeChanged);
      _observingRoutes = false;
    }
    _generation++;
    _entries.clear();
  }

  final _changes = StreamController<MediaOutboxEntry>.broadcast(sync: true);
  Stream<MediaOutboxEntry> get changes => _changes.stream;

  bool canStop(String? id) {
    final entry = _entries[id];
    return entry != null &&
        entry.task.current &&
        !entry.stopped &&
        entry.sending == null &&
        entry.message.status == MessageStatus.sending;
  }

  bool canCancel(String? id) {
    final entry = _entries[id];
    return entry != null &&
        entry.task.current &&
        !entry.stopped &&
        !entry.cancelling &&
        entry.message.status == MessageStatus.sending;
  }

  Future<bool> cancel(String? id) async {
    if (!canCancel(id)) return false;
    if (canStop(id)) return stop(id);
    final entry = _entries[id]!;
    entry.cancelling = true;
    try {
      await entry.sending;
      if (!entry.task.current) return false;
      if (entry.message.status == MessageStatus.sending) {
        final result = await _sender
            .lookup(entry.message, entry.task.target)
            .timeout(confirmTimeout);
        if (!entry.task.current || !result.isSuccess) return false;
      }
      if (entry.message.status == MessageStatus.succeeded) {
        await OpenIM.iMManager.messageManager
            .revokeMessage(
                conversationID: entry.task.target.conversationID,
                clientMsgID: id!)
            .timeout(confirmTimeout);
        if (!entry.task.current) return false;
        final info = RevokedInfo(
            clientMsgID: id, revokerID: entry.task.session.accountID);
        ChatHistoryCache.revokeMessage(entry.task.session.accountID, info);
        entry.message.update(ChatRevocationNotice.replace(entry.message, info));
      } else if (entry.message.status != MessageStatus.failed) {
        return false;
      }
      entry.stopped = true;
      _publish(entry);
      return true;
    } catch (_) {
      return false;
    } finally {
      entry.cancelling = false;
    }
  }

  bool stop(String? id) {
    if (!canStop(id)) return false;
    final entry = _entries[id]!;
    entry.stopped = true;
    entry.message.status = MessageStatus.failed;
    _publish(entry);
    return true;
  }

  bool retryStopped(Message message) {
    final old = _entries[message.clientMsgID];
    if (old == null || !old.stopped || !old.task.current) return false;
    final task = accept(old.task.target);
    final copy = Message.fromJson(message.toJson())
      ..status = MessageStatus.sending;
    task.stage(copy);
    unawaited(() async {
      try {
        await ChatMediaUpload(
                isClosed: () => !task.accepts(copy), onTransfer: task.transfer)
            .prepare(copy);
        await task.send(copy);
      } catch (_) {
        task.failed(copy);
      }
    }());
    return true;
  }

  MediaSendTask accept(FavoriteTarget target) {
    _entries.removeWhere((_, entry) => !entry.task.visible);
    if (!_observingRoutes) {
      Config.networkRouteRevision.addListener(_routeChanged);
      _observingRoutes = true;
    }
    return MediaSendTask._(
        this, MessageSendSession.capture(), target, _generation);
  }

  Iterable<MediaOutboxEntry> entries(String conversationID) =>
      _entries.values.where((e) =>
          e.task.visible &&
          e.task.target.conversationID == conversationID &&
          !ChatHistoryCache.isRemoved(
              e.task.session.accountID, e.message.clientMsgID));

  void _publish(MediaOutboxEntry entry) {
    if (!entry.task.visible) return;
    if (ChatHistoryCache.isRemoved(
        entry.task.session.accountID, entry.message.clientMsgID)) {
      return;
    }
    _changes.add(entry);
    // Successful rows now belong to the SDK; retain only a bounded recent
    // window to bridge a history read that began before the acknowledgement.
    final completed = _entries.entries
        .where((e) => e.value.message.status == MessageStatus.succeeded)
        .toList();
    for (final old in completed
        .take(completed.length > 100 ? completed.length - 100 : 0)) {
      _entries.remove(old.key);
    }
  }

  void _routeChanged() {
    for (final entry in _entries.values.toList()) {
      if (!entry.task.visible || entry.task.session.current) continue;
      entry.task._routeInterrupted = true;
      if (entry.message.status != MessageStatus.sending) continue;
      // Before submission the message definitely has not been sent. Once
      // submitted, retain uncertainty and keep observing the original ACK.
      if (entry.sending == null) {
        entry.message.status = MessageStatus.failed;
      } else {
        entry.transfer = const ChatTransferStatus(ChatTransferStage.unknown);
      }
      ChatMediaDiagnostics.record('route_changed',
          messageID: entry.message.clientMsgID,
          outcome:
              entry.sending == null ? 'failed_before_send' : 'unconfirmed');
      _publish(entry);
    }
  }
}

class MediaOutboxEntry {
  MediaOutboxEntry(this.task, this.message);
  final MediaSendTask task;
  final Message message;
  ChatTransferStatus transfer =
      const ChatTransferStatus(ChatTransferStage.queued);
  Future<void>? sending;
  bool stopped = false;
  bool cancelling = false;
}

class MediaSendTask {
  MediaSendTask._(this._owner, this.session, this.target, this._generation);
  final ChatMediaOutbox _owner;
  final MessageSendSession session;
  final FavoriteTarget target;
  final int _generation;
  bool _routeInterrupted = false;
  bool get visible =>
      _generation == _owner._generation && session.identityCurrent;
  bool get current =>
      !_routeInterrupted &&
      _generation == _owner._generation &&
      session.current;

  bool accepts(Message message) => current && !isStopped(message);

  bool isStopped(Message message) =>
      _owner._entries[message.clientMsgID]?.stopped == true ||
      _owner._entries[message.clientMsgID]?.task != this;

  void stage(Message message) {
    if (!current) return;
    message.recvID = target.userID;
    message.groupID = target.groupID;
    message.sessionType = target.sessionType;
    final entry = MediaOutboxEntry(this, message);
    _owner._entries[message.clientMsgID!] = entry;
    _owner._publish(entry);
  }

  void transfer(Message message, ChatTransferStatus status) {
    final entry = _owner._entries[message.clientMsgID];
    if (!accepts(message) || entry == null) return;
    entry.transfer = status;
    _owner._publish(entry);
  }

  void failed(Message message) {
    if (!accepts(message)) return;
    message.status = MessageStatus.failed;
    final entry = _owner._entries[message.clientMsgID];
    if (entry != null) _owner._publish(entry);
  }

  Future<void> send(Message message) {
    if (!accepts(message)) return Future.value();
    final entry = _owner._entries[message.clientMsgID]!;
    return entry.sending ??= _send(entry);
  }

  Future<void> _send(MediaOutboxEntry entry) async {
    final message = entry.message;
    transfer(message, const ChatTransferStatus(ChatTransferStage.confirming));
    // Keep observing the native result after the UI deadline. A timeout never
    // authorizes resending a message whose delivery is uncertain.
    final operation = _owner._sender.send(message, target).then((result) {
      ChatMediaDiagnostics.record('send_receipt',
          messageID: message.clientMsgID,
          outcome: result.status.name,
          error: result.errorCode == null
              ? null
              : PlatformException(code: result.errorCode!));
      if (!visible) return;
      if (result.isSuccess) {
        message.update(result.message!);
      } else if (result.status == FavoriteSendStatus.failed) {
        message.status = MessageStatus.failed;
      } else {
        entry.transfer = const ChatTransferStatus(ChatTransferStage.unknown);
      }
      _owner._publish(entry);
    });
    try {
      ChatMediaDiagnostics.record('send_message',
          messageID: message.clientMsgID, outcome: 'start');
      await operation.timeout(_owner.confirmTimeout);
    } on TimeoutException {
      if (visible && message.status == MessageStatus.sending) {
        entry.transfer = const ChatTransferStatus(ChatTransferStage.unknown);
        _owner._publish(entry);
      }
      ChatMediaDiagnostics.record('send_message',
          messageID: message.clientMsgID, outcome: 'unconfirmed_timeout');
    }
  }
}
