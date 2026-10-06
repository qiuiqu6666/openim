import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_message_focus_tokens.dart';

/// Owns temporary search feedback; the existing timeline owns the SDK window.
class ChatMessageFocusController {
  ChatMessageFocusController({
    required this.canFocus,
    required this.jump,
  });

  final bool Function(Message) canFocus;
  final Future<bool> Function(Message) jump;
  final highlightedID = RxnString();
  Timer? _highlightTimer;
  int _revision = 0;
  bool _disposed = false;

  Future<bool> focus(Message message) async {
    if (_disposed || !canFocus(message) || message.hasExpired) return false;
    cancel();
    final revision = _revision;
    final positioned = await jump(message);
    if (_disposed ||
        revision != _revision ||
        !positioned ||
        !canFocus(message) ||
        message.hasExpired) {
      return false;
    }
    highlightedID.value = message.clientMsgID;
    _highlightTimer = Timer(ChatMessageFocusTokens.highlightDuration, () {
      if (!_disposed && revision == _revision) highlightedID.value = null;
    });
    return true;
  }

  void cancel() {
    _revision++;
    _highlightTimer?.cancel();
    _highlightTimer = null;
    highlightedID.value = null;
  }

  void dispose() {
    cancel();
    _disposed = true;
  }
}
