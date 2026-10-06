import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

/// Tracks live messages received while the reversed chat list is away from zero.
///
/// History pages and the conversation's initial unread count must not be passed
/// to [recordIncoming]. This count describes unseen arrivals in this chat route,
/// independently of SDK read receipts.
class ChatNewMessageTracker {
  ChatNewMessageTracker({
    required String Function() currentUserID,
    required bool Function() isClosed,
  })  : _currentUserID = currentUserID,
        _isClosed = isClosed;

  final String Function() _currentUserID;
  final bool Function() _isClosed;
  final unseenCount = 0.obs;
  final awayFromLatest = false.obs;

  final _receivedIDs = <String>{};
  final _unseenIDs = <String>{};
  bool _closed = false;

  bool get _inactive => _closed || _isClosed();

  void updateScrollOffset(double pixels) {
    if (_inactive) return;
    awayFromLatest.value = pixels > 1;
    if (!awayFromLatest.value) {
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
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _clear();
  }
}
