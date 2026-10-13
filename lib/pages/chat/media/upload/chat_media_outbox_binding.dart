import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import '../../messages/chat_delivery_controller.dart';
import 'chat_media_outbox.dart';

/// Disposable presentation subscription; disposal never cancels delivery.
StreamSubscription<MediaOutboxEntry> bindMediaOutbox({
  required String conversationID,
  required RxList<Message> messages,
  required bool Function() isClosed,
  required Set<String> removedIDs,
  required ChatDeliveryController delivery,
  ChatMediaOutbox? outbox,
  void Function()? onAdded,
}) {
  var seeding = true;
  void apply(MediaOutboxEntry entry) {
    if (isClosed() ||
        !entry.task.current ||
        entry.task.target.conversationID != conversationID ||
        removedIDs.contains(entry.message.clientMsgID)) {
      return;
    }
    final existing = messages
        .firstWhereOrNull((m) => m.clientMsgID == entry.message.clientMsgID);
    if (existing?.status == MessageStatus.succeeded &&
        entry.message.status != MessageStatus.succeeded) {
      return;
    }
    final copy = Message.fromJson(entry.message.toJson());
    if (existing == null) {
      messages.add(copy);
      if (!seeding) onAdded?.call();
    } else {
      existing.update(copy);
      messages.refresh();
    }
    delivery.updateTransfer(copy.clientMsgID, entry.transfer);
  }

  final owner = outbox ?? ChatMediaOutbox.instance;
  final subscription = owner.changes.listen(apply);
  for (final entry in owner.entries(conversationID).toList()) {
    // Reconcile a cached pending row even if delivery finished while away.
    // Do not insert unrelated completed rows into a historical window.
    if (entry.message.status != MessageStatus.succeeded ||
        messages.any(
            (message) => message.clientMsgID == entry.message.clientMsgID)) {
      apply(entry);
    }
  }
  seeding = false;
  return subscription;
}
