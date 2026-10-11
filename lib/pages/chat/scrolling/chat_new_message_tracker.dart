import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

import 'chat_latest_scroll_tokens.dart';

/// Tracks live messages received while the reversed chat list is away from zero.
///
/// History pages and the conversation's initial unread count must not be passed
/// to [recordIncoming]. This count describes unseen arrivals in this chat route,
/// independently of SDK read receipts.
class ChatNewMessageTracker {
  ChatNewMessageTracker({
    required String Function() currentUserID,
    required bool Function() isClosed,
    double Function()? viewportDimension,
    bool Function()? hasMissingNewer,
  })  : _currentUserID = currentUserID,
        _isClosed = isClosed,
        _viewportDimension = viewportDimension,
        _hasMissingNewer = hasMissingNewer;

  final String Function() _currentUserID;
  final bool Function() _isClosed;
  final double Function()? _viewportDimension;
  final bool Function()? _hasMissingNewer;
  final unseenCount = 0.obs;
  final awayFromLatest = false.obs;
  final showBackToBottom = false.obs;

  final _receivedIDs = <String>{};
  final _unseenIDs = <String>{};
  bool _closed = false;

  bool get _inactive => _closed || _isClosed();

  void updateScrollOffset(double pixels, {bool viewportConfirmed = true}) {
    if (_inactive || !pixels.isFinite) return;
    final missingNewer = _hasMissingNewer?.call() == true;
    if (missingNewer || pixels > ChatLatestScrollTokens.leaveLatestDistance) {
      awayFromLatest.value = true;
    } else if (viewportConfirmed &&
        pixels <= ChatLatestScrollTokens.rejoinLatestDistance) {
      awayFromLatest.value = false;
    }
    final viewport = _viewportDimension?.call() ?? 0;
    final extent = viewport.isFinite && viewport > 0
        ? viewport
        : ChatLatestScrollTokens.fallbackViewportDimension;
    // History windows never count as latest, even at their local newest edge.
    // The button uses separate, larger show/hide distances.
    final ratio = showBackToBottom.value
        ? ChatLatestScrollTokens.hintHideViewportRatio
        : ChatLatestScrollTokens.hintShowViewportRatio;
    showBackToBottom.value = awayFromLatest.value &&
        (missingNewer || pixels >= extent * ratio);
    if (!awayFromLatest.value &&
        viewportConfirmed &&
        pixels <= ChatLatestScrollTokens.distanceEpsilon) {
      _unseenIDs.clear();
      unseenCount.value = 0;
    }
  }

  void recordIncoming(Message message) {
    if (_inactive ||
        message.contentType == MessageType.typing ||
        message.sendID == _currentUserID()) {
      return;
    }
    final id = message.clientMsgID;
    if (id == null || id.isEmpty || !_receivedIDs.add(id)) return;
    // Remember bottom-of-list arrivals too: replayed SDK callbacks are not new.
    if (awayFromLatest.value) {
      _unseenIDs.add(id);
      unseenCount.value = _unseenIDs.length;
    }
  }

  /// Called only after the message's bubble is actually visible in the viewport.
  void markVisible(String? id) {
    if (_inactive || !_unseenIDs.remove(id)) return;
    unseenCount.value = _unseenIDs.length;
  }

  /// Removes a deleted/revoked arrival without changing the scroll affordance.
  void remove(String? id) {
    if (_inactive || !_unseenIDs.remove(id)) return;
    unseenCount.value = _unseenIDs.length;
  }

  void reset() {
    if (_closed) return;
    _clear();
  }

  void _clear() {
    _receivedIDs.clear();
    _unseenIDs.clear();
    unseenCount.value = 0;
    awayFromLatest.value = false;
    showBackToBottom.value = false;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _clear();
  }
}
