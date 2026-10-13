import 'dart:convert';

import '../../group/member_actions/chat_member_action_result.dart';

/// Error-only SDK successes cover the whole request. Older per-member results
/// must name every requested member, so retries never include confirmed ones.
class GroupMemberBatchResult {
  const GroupMemberBatchResult(this.succeeded, this.failed);
  final Set<String> succeeded;
  final Set<String> failed;

  factory GroupMemberBatchResult.parse(Object? response, List<String> userIDs) {
    if (userIDs.isEmpty) return const GroupMemberBatchResult({}, {});
    Object? value = response;
    if (value is String && value.trim().isNotEmpty) {
      try {
        value = jsonDecode(value);
      } catch (_) {}
    }
    if (value is Map && value['data'] is List) {
      try {
        ensureChatMemberActionSucceeded({...value}..remove('data'),
            targetUserID: userIDs.first);
        value = value['data'];
      } catch (_) {
        return GroupMemberBatchResult({}, userIDs.toSet());
      }
    }
    if (value is List && value.isNotEmpty) {
      final succeeded = <String>{};
      final failed = userIDs.toSet();
      for (final entry in value) {
        if (entry is! Map || entry['userID'] is! String) continue;
        final id = entry['userID'] as String;
        if (!userIDs.contains(id)) continue;
        try {
          ensureChatMemberActionSucceeded(entry, targetUserID: id);
          succeeded.add(id);
          failed.remove(id);
        } catch (_) {
          succeeded.remove(id);
          failed.add(id);
        }
      }
      return GroupMemberBatchResult(succeeded, failed);
    }
    try {
      ensureChatMemberActionSucceeded(response, targetUserID: userIDs.first);
      return GroupMemberBatchResult(userIDs.toSet(), {});
    } catch (_) {
      return GroupMemberBatchResult({}, userIDs.toSet());
    }
  }
}
