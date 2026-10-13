import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Preserve the SDK's pinned/time ordering, sorting only changed/new rows.
List<ConversationInfo> mergeConversationOrder(List<ConversationInfo> previous,
    List<ConversationInfo> projected, Set<String> changedIDs) {
  final rank = <String, int>{
    for (var i = 0; i < previous.length; i++) previous[i].conversationID: i,
  };
  final byID = {for (final row in projected) row.conversationID: row};
  final unchanged = <ConversationInfo>[
    for (final row in previous)
      if (!changedIDs.contains(row.conversationID) &&
          byID.containsKey(row.conversationID))
        byID[row.conversationID]!,
  ];
  int compare(ConversationInfo a, ConversationInfo b) {
    final pinned =
        (b.isPinned == true ? 1 : 0).compareTo(a.isPinned == true ? 1 : 0);
    if (pinned != 0) return pinned;
    int time(ConversationInfo row) {
      final draft = row.draftTextTime ?? 0;
      final latest = row.latestMsgSendTime ?? 0;
      return draft > latest ? draft : latest;
    }

    final order = time(b).compareTo(time(a));
    if (order != 0) return order;
    return (rank[a.conversationID] ?? previous.length)
        .compareTo(rank[b.conversationID] ?? previous.length);
  }

  final changed = projected
      .where((row) =>
          changedIDs.contains(row.conversationID) ||
          !rank.containsKey(row.conversationID))
      .toList()
    ..sort(compare);
  final result = <ConversationInfo>[];
  var i = 0;
  var j = 0;
  while (i < unchanged.length && j < changed.length) {
    if (compare(unchanged[i], changed[j]) <= 0) {
      result.add(unchanged[i++]);
    } else {
      result.add(changed[j++]);
    }
  }
  result.addAll(unchanged.skip(i));
  result.addAll(changed.skip(j));
  return result;
}
