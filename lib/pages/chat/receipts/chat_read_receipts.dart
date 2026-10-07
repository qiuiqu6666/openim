import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../core/conversation_reads/conversation_read_request.dart';
import 'conversation_read_coordinator.dart';

/// Owns in-flight reads and coalesces visible message refreshes.
class ChatReadReceipts {
  ChatReadReceipts({
    required this.messageList,
    required ConversationInfo Function() conversation,
    required bool Function() isClosed,
    bool Function()? isActive,
    bool Function()? isSessionActive,
    bool Function()? canReadConversation,
    void Function(ConversationReadRequest)? onConversationRead,
  })  : _conversation = conversation,
        _isClosed = isClosed,
        _isActive = isActive ?? (() => true),
        _canReadConversation = canReadConversation ?? (() => true),
        _isSessionActive = isSessionActive,
        _onConversationRead = onConversationRead;
  final RxList<Message> messageList;
  final ConversationInfo Function() _conversation;
  final bool Function() _isClosed;
  final bool Function() _isActive;
  final bool Function() _canReadConversation;
  final bool Function()? _isSessionActive;
  final void Function(ConversationReadRequest)? _onConversationRead;
  bool _closed = false;
  bool get isClosed => _closed || _isClosed();
  ConversationInfo get conversationInfo => _conversation();
  static int get _timestamp => DateTime.now().millisecondsSinceEpoch;

  void applyC2CReceipt(List<ReadReceiptInfo> receipts, String? peerID) {
    if (isClosed) return;
    for (final receipt in receipts) {
      if (receipt.userID != peerID) continue;
      final ids = receipt.msgIDList?.toSet() ?? <String>{};
      for (final message in messageList) {
        if (ids.contains(message.clientMsgID)) {
          message.isRead = true;
          message.hasReadTime = _timestamp;
        }
      }
    }
    _refreshReadState();
  }

  void close() {
    _closed = true;
    _readRefreshTimer?.cancel();
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

  void invalidateViewport() {
    _visibleIDs.clear();
    _atLatest = false;
  }

  int _unreadRevision = 0;
  (String?, int?, int?, int)? _lastUnreadSnapshot;
  final _sdkInFlight = <String?, int>{};
  String? _confirmedTargetID;
  Timer? _readRefreshTimer;
  void _refreshReadState() {
    if (_readRefreshTimer != null || isClosed) return;
    _readRefreshTimer = Timer(Duration.zero, () {
      _readRefreshTimer = null;
      if (!isClosed) messageList.refresh();
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
    }, messageID: targetID, revision: _unreadRevision);
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
        knownUnreadCount: fromViewport ? _knownUnreadCount(info) : 0);
    final targetID = latest?.clientMsgID;
    _sdkInFlight[targetID] = (_sdkInFlight[targetID] ?? 0) + 1;
    _onConversationRead?.call(request);
    try {
      await OpenIM.iMManager.conversationManager.markConversationMessageAsRead(
          conversationID: request.conversationID);
      final succeeded = _isSessionActive?.call() ?? !isClosed;
      request.complete(succeeded);
      if (succeeded && !isClosed) _confirmedTargetID = targetID;
    } catch (_) {
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
        messageList.any((message) => message.clientMsgID == sdkLatestID);
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
    final visible = messageList
        .where((message) => _visibleIDs.contains(message.clientMsgID))
        .toList(growable: false);
    final canReadConversation = _latestIsVisible;
    if (canReadConversation &&
        (conversationInfo.unreadCount > 0 ||
            visible
                .any((message) => message.sendID != OpenIM.iMManager.userID))) {
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
        _refreshReadState();
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
        await markConversationRead(message.seq ?? 0);
      }
      if (isClosed) return;
      message.isRead = true;
      message.hasReadTime = _timestamp;
      if (message.attachedInfoElem?.isPrivateChat == true) {
        message.attachedInfoElem?.hasReadTime = _timestamp;
      }
      _refreshReadState();
    } catch (error) {
      if (error is! _ConversationReadCancelled) {
        Logger.print('Mark read failed: $error');
      }
    } finally {
      _readInFlight.remove(id);
    }
  }

  void clearUnreadCount({bool leaving = false}) {
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
