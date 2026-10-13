import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Settings accepted while a list query is pending override that query's older
/// fields, while its message, draft and unread metadata remain authoritative.
class ConversationSettingsProjection {
  final _pinned = <String, bool>{};
  final _receiveOptions = <String, int>{};

  void pinned(String id, bool value) => _pinned[id] = value;
  void receiveOption(String id, int value) => _receiveOptions[id] = value;

  ConversationInfo project(ConversationInfo info) {
    if (_pinned.containsKey(info.conversationID)) {
      info.isPinned = _pinned[info.conversationID];
    }
    if (_receiveOptions.containsKey(info.conversationID)) {
      info.recvMsgOpt = _receiveOptions[info.conversationID];
    }
    return info;
  }

  void clear() {
    _pinned.clear();
    _receiveOptions.clear();
  }
}
