import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Reuses identity collections when only receipts or message contents change.
class ChatMessageIndex {
  List<String> ids = const [];
  Map<String, int> indices = const {};
  Set<String> persisted = const {};

  void sync(List<Message> messages) {
    var same = ids.length == messages.length;
    if (same) {
      for (var i = 0; i < ids.length; i++) {
        if (ids[i] != (messages[messages.length - 1 - i].clientMsgID ?? '')) {
          same = false;
          break;
        }
      }
    }
    if (same) return;
    ids = List.generate(messages.length,
        (i) => messages[messages.length - 1 - i].clientMsgID ?? '');
    indices = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    persisted = ids.toSet();
  }
}
