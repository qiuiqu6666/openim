import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

/// A conversation-owned snapshot; cancellation never changes the text draft.
class PendingForward {
  PendingForward(List<Message> messages, this.recipient,
      {required this.merged, this.mergeTitle})
      : messages = List.unmodifiable(
            messages.map((message) => Message.fromJson(message.toJson())));

  final List<Message> messages;
  final dynamic recipient;
  final bool merged;
  final String? mergeTitle;
}

class PendingForwardController {
  final draft = Rxn<PendingForward>();
  final sending = false.obs;

  void cancel() {
    if (!sending.value) draft.value = null;
  }

  Future<bool> send(Future<bool> Function(PendingForward) deliver) async {
    final current = draft.value;
    if (current == null || sending.value) return false;
    sending.value = true;
    try {
      final sent = await deliver(current);
      if (sent && identical(draft.value, current)) draft.value = null;
      return sent;
    } finally {
      sending.value = false;
    }
  }
}
