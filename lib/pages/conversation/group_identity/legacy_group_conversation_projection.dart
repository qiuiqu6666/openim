import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../../services/legacy_identity/legacy_group_identity.dart';

/// Collapses the two local identities of a renamed group without writing to the
/// SDK. History availability must not decide whether an ordinary row duplicates
/// its replacement. Local-only messages and distinct drafts remain recoverable.
class LegacyGroupConversationProjection {
  LegacyGroupConversationProjection({this.server});

  final String? server;
  final _replaced = <String>{};

  List<ConversationInfo> project(Iterable<ConversationInfo> rows) {
    final byID = {for (final row in rows) row.conversationID: row};
    return byID.values.where((row) {
      final group = row.groupID;
      if (group == null ||
          row.conversationType != ConversationType.superGroup ||
          row.conversationID != 'sg_$group') {
        return true;
      }
      final target = LegacyGroupIdentity.canonical(group, server: server);
      if (target == group) return true;
      final next = byID['sg_$target'];
      if (next != null &&
          next.groupID == target &&
          next.conversationType == ConversationType.superGroup) {
        _replaced.add(row.conversationID);
      }
      if (!_replaced.contains(row.conversationID)) return true;

      // Projection never discards unfinished work or modifies either draft.
      // The separate migration may copy a draft and hide its old SDK row once
      // it can verify the local history. Keep recovery access until then.
      final draft = row.draftText ?? '';
      if (draft.isNotEmpty && draft != next?.draftText) return true;
      final latest = row.latestMsg;
      if (latest != null &&
          (latest.status == MessageStatus.sending ||
              latest.status == MessageStatus.failed ||
              ((latest.seq ?? 0) <= 0 &&
                  latest.status != MessageStatus.succeeded))) {
        return true;
      }
      return false;
    }).toList();
  }

  void clear() => _replaced.clear();
}
