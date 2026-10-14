import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

/// Keeps mention navigation independent of the conversation read receipt.
class ChatMentionController {
  ChatMentionController(
      {required this.userID,
      required this.isClosed,
      required this.search,
      required this.focus});

  final String Function() userID;
  final bool Function() isClosed;
  final Future<List<Message>> Function(int page) search;
  final Future<bool> Function(Message) focus;
  final pending = <Message>[].obs;
  final busy = false.obs;
  final _consumed = <String>{};
  bool _loading = false;
  ({int unreadCount, int latestSeq, bool hasMention})? _entry;
  int _attempts = 0;

  Future<void> retryEntry() async {
    final entry = _entry;
    if (entry == null ||
        _attempts >= 3 ||
        pending.isNotEmpty ||
        _consumed.isNotEmpty) {
      return;
    }
    await load(
        unreadCount: entry.unreadCount,
        latestSeq: entry.latestSeq,
        hasMention: entry.hasMention);
  }

  bool matches(Message message) {
    final targets = message.atTextElem?.atUserList ?? const <String>[];
    return message.sendID != userID() &&
        (targets.contains(userID()) || targets.contains('atAllTag'));
  }

  void add(Message message) {
    final id = message.clientMsgID;
    if (isClosed() ||
        id == null ||
        id.isEmpty ||
        !matches(message) ||
        _consumed.contains(id) ||
        pending.any((m) => m.clientMsgID == id)) {
      return;
    }
    pending.add(message);
    pending.sort((a, b) => (a.sendTime ?? 0).compareTo(b.sendTime ?? 0));
  }

  void remove(String id) {
    _consumed.add(id);
    pending.removeWhere((m) => m.clientMsgID == id);
  }

  Future<void> load(
      {required int unreadCount,
      required int latestSeq,
      required bool hasMention}) async {
    if (_loading || isClosed() || (!hasMention && unreadCount <= 0)) return;
    _entry = (
      unreadCount: unreadCount,
      latestSeq: latestSeq,
      hasMention: hasMention
    );
    _attempts++;
    _loading = true;
    final firstUnreadSeq = latestSeq - unreadCount;
    try {
      for (var page = 1; !isClosed(); page++) {
        final messages = await search(page);
        if (isClosed() || messages.isEmpty) break;
        var reachedRead = false;
        for (final message in messages) {
          final seq = message.seq ?? 0;
          final unread = latestSeq > 0 && seq > 0
              ? seq > firstUnreadSeq && seq <= latestSeq
              : message.isRead != true;
          if (latestSeq > 0 && seq > 0 && seq <= firstUnreadSeq) {
            reachedRead = true;
          }
          if (hasMention && unreadCount == 0 && matches(message)) {
            add(message);
            return;
          }
          if (unread) add(message);
        }
        if ((reachedRead && unreadCount > 0) || messages.length < 50) break;
      }
    } finally {
      _loading = false;
    }
  }

  Future<bool> jump() async {
    if (busy.value || pending.isEmpty || isClosed()) return false;
    busy.value = true;
    final target = pending.first;
    try {
      final found = await focus(target);
      if (!isClosed() && found) remove(target.clientMsgID!);
      return found;
    } finally {
      if (!isClosed()) busy.value = false;
    }
  }
}
