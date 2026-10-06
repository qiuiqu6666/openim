import 'package:azlistview/azlistview.dart';

import '../../../contacts/directory/contact_directory_indexer.dart';
import 'chat_history_sender_source.dart';

/// List projection only: selection always returns the original SDK-backed sender.
class ChatHistorySenderRow extends ISuspensionBean {
  ChatHistorySenderRow({required this.sender, required this.index}) {
    isShowSuspension = index.showHeader;
  }

  final ChatHistorySender sender;
  final ContactNameIndex index;

  @override
  String getSuspensionTag() => index.tagIndex ?? '#';
}

/// Call after loading/changing the directory, not from a widget's build method.
/// The shared contact indexer owns pinyin, same-letter ordering and # placement.
List<ChatHistorySenderRow> buildChatHistorySenderDirectory(
  Iterable<ChatHistorySender> source, {
  Iterable<ChatHistorySenderRow> previous = const [],
}) {
  final senders = <String, ChatHistorySender>{};
  for (final sender in source) {
    if (sender.userID.trim().isNotEmpty) {
      senders.putIfAbsent(sender.userID, () => sender);
    }
  }
  final cached = {
    for (final row in previous) row.sender.userID: row.index,
  };
  final indexed = buildContactNameIndex([
    for (final sender in senders.values)
      if (cached[sender.userID]?.displayName == sender.name)
        cached[sender.userID]!
      else
        ContactNameIndex(userID: sender.userID, displayName: sender.name),
  ]);
  return [
    for (final index in indexed)
      ChatHistorySenderRow(sender: senders[index.userID]!, index: index),
  ];
}
