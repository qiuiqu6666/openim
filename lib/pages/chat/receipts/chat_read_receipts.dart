import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../core/conversation_reads/conversation_read_request.dart';
import 'conversation_read_coordinator.dart';
import 'chat_read_diagnostics.dart';

/// Owns in-flight reads and coalesces visible message refreshes.
class ChatReadReceipts {
  ChatReadReceipts({
    required this.messageList,
    DateTime Function()? now,
    required ConversationInfo Function() conversation,
    required bool Function() isClosed,
    bool Function()? isActive,
    bool Function()? isSessionActive,
    bool Function()? canReadConversation,
    void Function(ConversationReadRequest)? onConversationRead,
    void Function(Set<String> messageIDs)? onReadStateChanged,
    ChatReadDiagnostics? diagnostics,
    Map<String, Object?> Function()? diagnosticState,
  })  : _diagnostics = diagnostics,
        _diagnosticState = diagnosticState,
        _now = now ?? DateTime.now,
        _conversation = conversation,
        _isClosed = isClosed,
        _isActive = isActive ?? (() => true),
        _canReadConversation = canReadConversation ?? (() => true),
        _isSessionActive = isSessionActive,
        _onConversationRead = onConversationRead,
        _onReadStateChanged = onReadStateChanged {
    _indexWorker = ever(messageList, (_) {
      _messageIndexDirty = true;
      _messageIndex.clear();
      if (!this.isClosed && _confirmedReads.isNotEmpty) {
        for (final message in messageList) {
          final time = _confirmedReads[message.clientMsgID];
          if (time != null && _applyRead(message, time)) {
            _refreshReadState(message);
          }
        }
      }
    });
  }
  final DateTime Function() _now;
  final ChatReadDiagnostics? _diagnostics;
  final Map<String, Object?> Function()? _diagnosticState;

  void _diagnose(String event,
      {Map<String, Object?> extra = const {}, bool deduplicate = false}) {
    if (_diagnostics == null) return;
    final latest = messageList.lastOrNull;
    _diagnostics.record(
        event,
        {
          ...?_diagnosticState?.call(),
          'closed': isClosed,
          'active': _isActive(),
          'gateAllowed': _canReadConversation(),
          'atLatest': _atLatest,
          'visibleCount': _visibleIDs.length,
          'latestVisible':
              latest != null && _visibleIDs.contains(latest.clientMsgID),
          'latestID': latest?.clientMsgID,
          'latestSeq': latest?.seq,
          'latestIsRead': latest?.isRead,
          'previewID': conversationInfo.latestMsg?.clientMsgID,
          'previewPresent': conversationInfo.latestMsg?.clientMsgID == null ||
              _messagesByID
                  .containsKey(conversationInfo.latestMsg?.clientMsgID),
          'unreadCount': conversationInfo.unreadCount,
          ...extra,
        },
        deduplicate: deduplicate);
  }

  final RxList<Message> messageList;
  final ConversationInfo Function() _conversation;
  final bool Function() _isClosed;
  final bool Function() _isActive;
  final bool Function() _canReadConversation;
  final bool Function()? _isSessionActive;
  final void Function(ConversationReadRequest)? _onConversationRead;
  final void Function(Set<String> messageIDs)? _onReadStateChanged;
  bool _closed = false;
  bool get isClosed => _closed || _isClosed();
  ConversationInfo get conversationInfo => _conversation();
  static int get _timestamp => DateTime.now().millisecondsSinceEpoch;

  late final Worker _indexWorker;
  bool _messageIndexDirty = true;
  final _messageIndex = <String, Message>{};
  // Route/session-owned receipts also cover buffered rows and in-flight history.
  // Never infer reads from an incoming reply; only confirmed SDK IDs enter here.
  final _confirmedReads = <String, int>{};
  static const _maxConfirmedReads = 4096;

  bool _applyRead(Message message, int time) {
    if (message.isRead == true && (message.hasReadTime ?? 0) > 0) return false;
    message.isRead = true;
    if ((message.hasReadTime ?? 0) <= 0) message.hasReadTime = time;
    return true;
  }

  Map<String, Message> get _messagesByID {
    if (_messageIndexDirty) {
      _messageIndex.clear();
      for (final message in messageList) {
        final id = message.clientMsgID;
        if (id != null) _messageIndex[id] = message;
      }
      _messageIndexDirty = false;
    }
    return _messageIndex;
  }

  void applyC2CReceipt(List<ReadReceiptInfo> receipts, String? peerID) {
    if (isClosed || peerID == null || peerID.isEmpty) return;
    for (final receipt in receipts) {
      if (receipt.userID != peerID) continue;
      final ids = receipt.msgIDList?.toSet() ?? <String>{};
      for (final id in ids) {
        if (id.isEmpty) continue;
        final time = _confirmedReads.putIfAbsent(id, () => _timestamp);
        while (_confirmedReads.length > _maxConfirmedReads) {
          _confirmedReads.remove(_confirmedReads.keys.first);
        }
        final message = _messagesByID[id];
        if (message != null && _applyRead(message, time)) {
          _refreshReadState(message);
        }
      }
    }
  }

  void close() {
    _closed = true;
    _readRefreshTimer?.cancel();
    _viewportReadTimer?.cancel();
    _indexWorker.dispose();
    _messageIndex.clear();
    _confirmedReads.clear();
    _pendingReadStateIDs.clear();
  }

  void markMessageAsRead(Message message, bool visible) {
    if (!isClosed &&
        _isActive() &&
        visible &&
        _readContentWhenVisible(message)) {
      unawaited(markRead(message));
    }
  }

  final _readInFlight = <String>{};
  final _conversationReads = ConversationReadCoordinator();
  Set<String> _visibleIDs = {};
  bool _atLatest = false;

  Timer? _viewportReadTimer;
  DateTime? _lastViewportRead;
  static const viewportReadInterval = Duration(milliseconds: 250);

  void invalidateViewport() {
    _diagnose('viewport_invalidated');
    _viewportReadTimer?.cancel();
    _viewportReadTimer = null;
    // A later route entry gets its first painted read immediately.
    _lastViewportRead = null;
    _visibleIDs.clear();
    _atLatest = false;
  }

  int _unreadRevision = 0;
  (String?, int?, int?, int)? _lastUnreadSnapshot;
  final _sdkInFlight = <String?, int>{};
  String? _confirmedTargetID;
  Timer? _readRefreshTimer;
  final _pendingReadStateIDs = <String>{};
  void _refreshReadState(Message message) {
    if (isClosed) return;
    final id = message.clientMsgID;
    if (id == null || id.isEmpty) return;
    _pendingReadStateIDs.add(id);
    if (_readRefreshTimer != null) return;
    _readRefreshTimer = Timer(Duration.zero, () {
      _readRefreshTimer = null;
      final ids = Set<String>.unmodifiable(_pendingReadStateIDs);
      _pendingReadStateIDs.clear();
      if (isClosed || ids.isEmpty) return;
      final publish = _onReadStateChanged;
      if (publish != null) {
        publish(ids);
      } else {
        // Consumers without row subscriptions retain the previous contract.
        messageList.refresh();
      }
    });
  }

  Future<void> markConversationRead([int sequence = 0]) =>
      _markConversationRead(sequence);

  Future<void> _markConversationRead(int sequence,
      {bool requireVisible = false}) {
    if (isClosed || !_isActive()) return Future<void>.value();
    final targetID = messageList.lastOrNull?.clientMsgID;
    final newestSequence = messageList.isEmpty ? 0 : messageList.last.seq ?? 0;
    if (newestSequence > sequence) sequence = newestSequence;
    return _conversationReads.markRead(sequence, () async {
      if (isClosed || !_isActive() || !_canReadConversation()) {
        throw const _ConversationReadCancelled();
      }
      if (requireVisible &&
          (!_latestIsVisible ||
              targetID != messageList.lastOrNull?.clientMsgID)) {
        throw const _ConversationReadCancelled();
      }
      await _sendConversationRead(fromViewport: requireVisible);
    },
        messageID: targetID,
        identitySequence: newestSequence,
        revision: _unreadRevision);
  }

  Future<void> _sendConversationRead({bool fromViewport = false}) async {
    // A full conversation read also consumes rows absent from the visible IDs.
    // The route can defer it until all entering rows have fully painted.
    if (!_canReadConversation()) throw const _ConversationReadCancelled();
    final info = conversationInfo;
    final latest = messageList.lastOrNull;
    // The message callback can precede its conversation metadata callback.
    // Capture the actual painted target, rather than the older preview.
    final request = ConversationReadRequest.capture(info,
        visibleLatestMessage: fromViewport ? latest : null,
        knownUnreadCount: fromViewport ? _knownUnreadCount(info) : 0,
        retryMessageIDs: fromViewport && info.isPrivateChat != true
            ? _visibleIDs
                .map((id) => _messagesByID[id])
                .whereType<Message>()
                .where((message) =>
                    _incomingContent(message) &&
                    (message.seq ?? 0) > 0 &&
                    message.attachedInfoElem?.isPrivateChat != true &&
                    message.clientMsgID?.isNotEmpty == true)
                .map((message) => message.clientMsgID!)
            : const []);
    final targetID = latest?.clientMsgID;
    _diagnose('request_start', extra: {'fromViewport': fromViewport});
    _sdkInFlight[targetID] = (_sdkInFlight[targetID] ?? 0) + 1;
    _onConversationRead?.call(request);
    try {
      if (fromViewport) _lastViewportRead = _now();
      await OpenIM.iMManager.conversationManager.markConversationMessageAsRead(
          conversationID: request.conversationID);
      final succeeded = _isSessionActive?.call() ?? !isClosed;
      request.complete(succeeded);
      _diagnose('request_result', extra: {
        'success': succeeded,
        'targetID': targetID,
        'targetSeq': latest?.seq
      });
      if (succeeded && !isClosed) _confirmedTargetID = targetID;
    } catch (error) {
      _diagnose('request_error', extra: {
        'errorType': error.runtimeType.toString(),
        'errorCode': error is PlatformException ? error.code : null
      });
      request.complete(false);
      rethrow;
    } finally {
      final remaining = (_sdkInFlight[targetID] ?? 1) - 1;
      if (remaining == 0) {
        _sdkInFlight.remove(targetID);
      } else {
        _sdkInFlight[targetID] = remaining;
      }
    }
  }

  int _knownUnreadCount(ConversationInfo info) {
    final previewIndex = messageList.indexWhere(
        (message) => message.clientMsgID == info.latestMsg?.clientMsgID);
    var count = 0;
    for (final message in messageList.skip(previewIndex + 1)) {
      if (_incomingContent(message)) ++count;
    }
    if (count == 0 && _incomingContent(messageList.last)) count = 1;
    return count;
  }

  bool _incomingContent(Message message) =>
      message.sendID != OpenIM.iMManager.userID &&
      message.contentType != null &&
      message.contentType! < 1000 &&
      message.contentType != MessageType.typing;

  bool get _latestIsVisible => _canReadLatest();

  bool _canReadLatest({bool leaving = false}) {
    if (isClosed ||
        !_canReadConversation() ||
        (!leaving && !_isActive()) ||
        !_atLatest ||
        messageList.isEmpty) {
      return false;
    }
    final latestID = messageList.last.clientMsgID;
    if (latestID == null || !_visibleIDs.contains(latestID)) return false;
    // The SDK may announce a newer message before its timeline callback.
    final sdkLatestID = conversationInfo.latestMsg?.clientMsgID;
    return sdkLatestID == null ||
        sdkLatestID.isEmpty ||
        _messagesByID.containsKey(sdkLatestID);
  }

  bool _readContentWhenVisible(Message message) {
    final type = message.contentType;
    if (type == null || type >= 1000 || type == MessageType.voice) return false;
    final data = IMUtils.parseCustomMessage(message);
    return data == null || data['viewType'] != CustomMessageType.call;
  }

  /// The painted viewport is already guarded by foreground and route focus.
  /// Conversation unread state is independent of voice playback/private burns.
  Future<void> markVisibleMessages(Iterable<String> ids,
      {bool atLatest = true}) async {
    if (isClosed || !_isActive()) return;
    _visibleIDs = ids.toSet();
    // A blocked observation cannot later authorize a close-time full clear
    // merely because motion finished under a covered/background route.
    _atLatest = atLatest && _canReadConversation();
    // Scroll/layout frames usually repeat the same small visible range. The
    // index is rebuilt only after a message-list mutation, not on each frame.
    final index = _messagesByID;
    final visible = _visibleIDs
        .map((id) => index[id])
        .whereType<Message>()
        .toList(growable: false);
    final canReadConversation = _latestIsVisible;
    _diagnose('viewport_decision',
        extra: {'allowed': canReadConversation}, deduplicate: true);
    if (canReadConversation &&
        (conversationInfo.unreadCount > 0 ||
            visible
                .any((message) => message.sendID != OpenIM.iMManager.userID))) {
      // Keep private/expiring content on its immediate visibility path.
      final elapsed = _lastViewportRead == null
          ? viewportReadInterval
          : _now().difference(_lastViewportRead!);
      if (conversationInfo.isPrivateChat != true &&
          !visible.any((m) => m.attachedInfoElem?.isPrivateChat == true) &&
          elapsed < viewportReadInterval) {
        _viewportReadTimer ??= Timer(viewportReadInterval - elapsed, () {
          _viewportReadTimer = null;
          if (!isClosed && _isActive() && _latestIsVisible) {
            unawaited(
                markVisibleMessages(_visibleIDs.toList(), atLatest: _atLatest));
          }
        });
        return;
      }
      _viewportReadTimer?.cancel();
      _viewportReadTimer = null;
      try {
        await _markConversationRead(0, requireVisible: true);
      } catch (error) {
        if (error is! _ConversationReadCancelled) {
          Logger.print('Visible conversation read failed: $error');
        }
        return;
      }
    }
    if (isClosed || !_isActive()) return;
    final privateReads = <Future<void>>[];
    for (final message in visible) {
      if (!_readContentWhenVisible(message)) continue;
      if (message.attachedInfoElem?.isPrivateChat == true) {
        privateReads.add(markRead(message));
      } else if (canReadConversation &&
          message.sendID != OpenIM.iMManager.userID &&
          message.isRead != true) {
        message.isRead = true;
        message.hasReadTime = _timestamp;
        _refreshReadState(message);
      }
    }
    await Future.wait(privateReads);
  }

  /// A later unread snapshot must not be hidden by the sequence deduplication.
  void conversationChanged() {
    if (isClosed) return;
    final info = conversationInfo;
    if (info.unreadCount == 0) {
      _lastUnreadSnapshot = null;
      return;
    }
    final snapshot = (
      info.latestMsg?.clientMsgID,
      info.latestMsg?.seq,
      info.latestMsgSendTime,
      info.unreadCount
    );
    if (snapshot == _lastUnreadSnapshot) return;
    _lastUnreadSnapshot = snapshot;
    ++_unreadRevision;
    if (_latestIsVisible) {
      unawaited(markVisibleMessages(_visibleIDs, atLatest: _atLatest));
    }
  }

  Future<void> markRead(Message message) async {
    if (isClosed) return;
    final id = message.clientMsgID;
    if (id == null ||
        message.isRead == true ||
        message.sendID == OpenIM.iMManager.userID ||
        !_readInFlight.add(id)) {
      return;
    }
    try {
      if (message.attachedInfoElem?.isPrivateChat == true) {
        await OpenIM.iMManager.messageManager.markMessagesAsReadByMsgID(
            conversationID: conversationInfo.conversationID,
            messageIDList: [id]);
      } else {
        // Hearing one older voice does not prove the newer conversation was
        // seen. Its local voiceHeard flag is independent from SDK unread.
        final voice = message.contentType == MessageType.voice;
        if (voice && !_latestIsVisible) return;
        await _markConversationRead(message.seq ?? 0, requireVisible: voice);
      }
      if (isClosed) return;
      message.isRead = true;
      message.hasReadTime = _timestamp;
      if (message.attachedInfoElem?.isPrivateChat == true) {
        message.attachedInfoElem?.hasReadTime = _timestamp;
      }
      _refreshReadState(message);
    } catch (error) {
      if (error is! _ConversationReadCancelled) {
        Logger.print('Mark read failed: $error');
      }
    } finally {
      _readInFlight.remove(id);
    }
  }

  void clearUnreadCount({bool leaving = false}) {
    _diagnose('leave_decision', extra: {
      'leaving': leaving,
      'allowed': _canReadLatest(leaving: leaving)
    });
    final targetID = messageList.lastOrNull?.clientMsgID;
    if (_canReadLatest(leaving: leaving) &&
        !_sdkInFlight.containsKey(targetID) &&
        (conversationInfo.unreadCount > 0 || targetID != _confirmedTargetID)) {
      // Start now, before route disposal. A queued full-clear after leaving
      // could consume a later message that the user has never seen.
      unawaited(
          _sendConversationRead(fromViewport: true).catchError((Object error) {
        Logger.print('Clear unread failed: $error');
      }));
    }
  }
}

class _ConversationReadCancelled implements Exception {
  const _ConversationReadCancelled();
}
