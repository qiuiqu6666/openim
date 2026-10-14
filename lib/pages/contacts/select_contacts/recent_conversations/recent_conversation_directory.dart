import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'recent_membership_cache.dart';

class RecentConversationDirectoryResult {
  const RecentConversationDirectoryResult(this.rows, this.failed);
  final List<ConversationInfo> rows;
  final bool failed;
}

/// One failed membership check cannot discard unrelated chats. Bound native
/// queries and retain the original SDK order after independent checks finish.
class RecentConversationDirectory {
  const RecentConversationDirectory(this.isJoinedGroup);
  final Future<bool> Function(String) isJoinedGroup;

  Future<RecentConversationDirectoryResult> load(List<ConversationInfo> rows,
      {required bool Function(ConversationInfo) isVisible,
      required bool Function() isCurrent,
      RecentMembershipCache? cache,
      void Function(List<ConversationInfo>)? onUpdate,
      void Function(String)? onExcluded}) async {
    cache ??= RecentMembershipCache();
    final results = List<ConversationInfo?>.filled(rows.length, null);
    bool visible(ConversationInfo row) =>
        isVisible(row) && row.conversationType != ConversationType.notification;
    List<ConversationInfo> snapshot() => results
        .whereType<ConversationInfo>()
        .where((row) => !row.isGroupChat || cache!.contains(row.groupID))
        .toList();
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (visible(row) && (!row.isGroupChat || cache.contains(row.groupID))) {
        results[index] = row;
      }
    }
    if (isCurrent()) onUpdate?.call(snapshot());
    Timer? publishTimer;
    void publishSoon() {
      if (onUpdate == null || publishTimer != null) return;
      publishTimer = Timer(const Duration(milliseconds: 16), () {
        publishTimer = null;
        if (isCurrent()) onUpdate(snapshot());
      });
    }

    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (isCurrent() && next < rows.length) {
        final index = next++;
        final row = rows[index];
        if (!visible(row) || !row.isGroupChat) {
          continue;
        }
        final id = row.groupID;
        if (id == null || id.isEmpty) continue;
        final revision = cache!.begin(id);
        try {
          final joined =
              await isJoinedGroup(id).timeout(const Duration(seconds: 5));
          if (isCurrent() && cache.complete(id, revision, joined)) {
            results[index] = joined ? row : null;
            if (!joined) onExcluded?.call(id);
            publishSoon();
          }
        } catch (_) {
          if (isCurrent()) failed = true;
        }
      }
    }

    await Future.wait(List.generate(math.min(4, rows.length), (_) => worker()));
    publishTimer?.cancel();
    if (isCurrent()) onUpdate?.call(snapshot());
    return RecentConversationDirectoryResult(
        isCurrent() ? snapshot() : [], failed);
  }

  /// Always queries the SDK afresh. Cached display evidence never authorizes
  /// sending. Failure/timeout/obsolete session fails the whole confirmation.
  Future<bool> validateForSend(Iterable<String> groupIDs,
      {required bool Function() isCurrent,
      required RecentMembershipCache cache,
      void Function(String)? onExcluded}) async {
    final ids = groupIDs.toSet().toList();
    var next = 0;
    var valid = true;
    Future<void> worker() async {
      while (isCurrent() && next < ids.length) {
        final id = ids[next++];
        final revision = cache.begin(id);
        try {
          final joined =
              await isJoinedGroup(id).timeout(const Duration(seconds: 5));
          if (!isCurrent()) return;
          if (!cache.complete(id, revision, joined) || !joined) valid = false;
          if (!joined) onExcluded?.call(id);
        } catch (_) {
          valid = false;
        }
      }
    }

    await Future.wait(List.generate(math.min(4, ids.length), (_) => worker()));
    return isCurrent() && valid;
  }
}
