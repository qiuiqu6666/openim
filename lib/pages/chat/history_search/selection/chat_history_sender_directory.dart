import 'chat_history_sender_source.dart';

/// Keep the SDK's member order. Each page only appends new IDs, so loading more
/// cannot move existing rows or replace the original sender used for selection.
class ChatHistorySenderDirectory {
  final _ids = <String>{};
  final _members = <ChatHistorySender>[];

  int get length => _members.length;
  bool get isEmpty => _members.isEmpty;
  ChatHistorySender operator [](int index) => _members[index];

  bool addPage(Iterable<ChatHistorySender> items) {
    final previousLength = _members.length;
    for (final member in items) {
      if (member.userID.trim().isNotEmpty && _ids.add(member.userID)) {
        _members.add(member);
      }
    }
    return _members.length != previousLength;
  }

  void clear() {
    _ids.clear();
    _members.clear();
  }
}
