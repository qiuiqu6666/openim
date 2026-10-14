import 'dart:collection';

import '../data/data.dart';
import '../models/customer_service_chat_entry.dart';

/// Index once per batch, preserve local sends, then order once. A null result
/// means callers can retain both their rows and their notification revision.
List<CustomerServiceChatEntry>? mergeCustomerServiceHistory(
  List<CustomerServiceChatEntry> previous,
  Iterable<CustomerServiceMessage> incoming, {
  String? conversationId,
  String? echoId,
}) {
  final rows = LinkedHashSet<CustomerServiceChatEntry>.identity()
    ..addAll(previous);
  final ids = <String, CustomerServiceChatEntry>{};
  final echoes = <String, CustomerServiceChatEntry>{};
  final order = <CustomerServiceChatEntry, int>{};
  var sequence = 0;
  void index(CustomerServiceChatEntry entry) {
    final id = entry.message?.id ?? '';
    if (id.isNotEmpty) ids[id] = entry;
    if (entry.echoId.isNotEmpty) echoes[entry.echoId] = entry;
    order[entry] = sequence++;
  }

  void remove(CustomerServiceChatEntry entry) {
    rows.remove(entry);
    final id = entry.message?.id;
    if (ids[id] == entry) ids.remove(id);
    if (echoes[entry.echoId] == entry) echoes.remove(entry.echoId);
  }

  for (final entry in previous) {
    index(entry);
  }
  var changes = 0;
  CustomerServiceChatEntry? lastChanged;
  for (final message in incoming) {
    if (message.content.trim().isEmpty &&
        message.attachments.isEmpty &&
        echoId == null) {
      continue;
    }
    if (message.conversationId.isNotEmpty &&
        conversationId != null &&
        message.conversationId != conversationId) {
      continue;
    }
    final echo = echoId ?? message.echoId;
    final matches = <CustomerServiceChatEntry>{
      if (message.id.isNotEmpty && ids[message.id] != null) ids[message.id]!,
      if (echo.isNotEmpty && echoes[echo] != null) echoes[echo]!,
    }.toList()
      ..sort((a, b) => order[a]!.compareTo(order[b]!));
    CustomerServiceChatEntry? local;
    for (final entry in matches) {
      local ??= entry;
      if (entry.upload != null || entry.text.isNotEmpty) {
        local = entry;
        break;
      }
    }
    final resolvedEcho = echo.isNotEmpty ? echo : local?.echoId ?? '';
    if (matches.length == 1 &&
        local!.echoId == resolvedEcho &&
        local.state == CustomerServiceSendState.sent &&
        _sameMessage(local.message, message)) {
      continue;
    }
    for (final entry in matches) {
      remove(entry);
    }
    final entry = CustomerServiceChatEntry(
      echoId: resolvedEcho,
      text: local?.text ?? '',
      upload: local?.upload,
      message: message,
    );
    rows.add(entry);
    index(entry);
    // A content-only correction must not move rows with equal/unknown dates.
    if (matches.isNotEmpty) order[entry] = order[matches.first]!;
    changes++;
    lastChanged = entry;
  }
  if (changes == 0) return null;
  final result = rows.toList();
  int compare(CustomerServiceChatEntry a, CustomerServiceChatEntry b) {
    final first = a.message, next = b.message;
    if (first == null || next == null) {
      if (first != null) return -1;
      if (next != null) return 1;
    } else {
      if (first.createdAt != null && next.createdAt != null) {
        final compared = first.createdAt!.compareTo(next.createdAt!);
        if (compared != 0) return compared;
      }
      final firstId = int.tryParse(first.id), nextId = int.tryParse(next.id);
      if (firstId != null && nextId != null && firstId != nextId) {
        return firstId.compareTo(nextId);
      }
    }
    return order[a]!.compareTo(order[b]!);
  }

  if (changes == 1) {
    // Socket events and send acknowledgements remain linear in history size,
    // instead of re-sorting every old row for a single changed message.
    final entry = lastChanged!;
    result.remove(entry);
    final next = result.indexWhere((row) => compare(entry, row) < 0);
    result.insert(next < 0 ? result.length : next, entry);
  } else {
    result.sort(compare);
  }
  return result;
}

bool _sameMessage(CustomerServiceMessage? a, CustomerServiceMessage b) {
  if (identical(a, b)) return true;
  if (a == null ||
      a.id != b.id ||
      a.content != b.content ||
      a.echoId != b.echoId ||
      a.conversationId != b.conversationId ||
      a.messageType != b.messageType ||
      a.createdAt != b.createdAt ||
      a.attachments.length != b.attachments.length) {
    return false;
  }
  for (var i = 0; i < a.attachments.length; i++) {
    final left = a.attachments[i], right = b.attachments[i];
    if (left.fileType != right.fileType ||
        left.dataUrl != right.dataUrl ||
        left.thumbUrl != right.thumbUrl ||
        left.fileName != right.fileName ||
        left.width != right.width ||
        left.height != right.height) {
      return false;
    }
  }
  return true;
}
