import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../conversation_logic.dart';
import '../folders/conversation_folder_controller.dart';
import 'conversation_peek.dart';
import 'conversation_peek_actions.dart';

/// Adapts the existing feed actions without transferring their state ownership
/// to the preview. Resolves the live conversation again after route dismissal.
Future<void> showFeedConversationPeek({
  required BuildContext context,
  required ConversationInfo conversation,
  required ConversationLogic logic,
  required bool Function() isActive,
  required Future<void> Function(ConversationInfo) onDelete,
  ConversationFolderController? folders,
  Future<void> Function(ConversationInfo, Future<void> Function())? perform,
}) async {
  final id = conversation.conversationID;
  ConversationInfo? current() {
    for (final info in logic.list) {
      if (info.conversationID == id) return info;
    }
    return null;
  }

  bool active() =>
      context.mounted &&
      isActive() &&
      logic.isSessionActive &&
      current() != null;
  Future<void> run(Future<void> Function(ConversationInfo) action) async {
    if (!active()) return;
    final info = current()!;
    if (perform != null) {
      await perform(info, () => action(info));
    } else {
      await action(info);
    }
  }

  if (!active()) return;
  ConversationPeekActions snapshot() {
    final info = current() ?? conversation;
    final pinned = info.isPinned == true;
    final muted = logic.isNotDisturb(info);
    final archived = logic.isArchived(info);
    final folderID = logic.folderID(info);
    return ConversationPeekActions(
      isAvailable: active(),
      isPinned: pinned,
      isMuted: muted,
      isArchived: archived,
      hasFolder: folderID != null,
      onOpenChat: () {
        if (active()) logic.toChat(conversationInfo: current()!);
      },
      onArchive: () => run((info) async {
        await logic.updateOrganizer(info,
            folderID: logic.folderID(info), archived: !archived);
      }),
      onAddToFolder: folders == null
          ? null
          : () => run((info) => folders.chooseFolder(context, info)),
      onRemoveFromFolder: folders == null || folderID == null
          ? null
          : () => run((info) async {
                if (logic.folderID(info) == folderID) {
                  await folders.removeFromFolder(info);
                }
              }),
      onTogglePin: () => run((info) => logic.setPinned(info, !pinned)),
      onToggleMute: () => run((info) => logic.setNotDisturb(info, !muted)),
      // Deletion already owns its confirmation and pending-action guard.
      onDelete: () async {
        if (active()) await onDelete(current()!);
      },
    );
  }

  final actions = ValueNotifier(snapshot());
  void refresh() => actions.value = snapshot();
  final subscriptions = <StreamSubscription<dynamic>>[
    logic.list.listen((_) => refresh()),
    logic.states.listen((_) => refresh()),
    logic.folders.listen((_) => refresh()),
  ];
  try {
    await showConversationPeek(
      context: context,
      conversation: conversation,
      displayName: logic.getShowName(conversation),
      actions: actions.value,
      liveActions: actions,
      isActive: active,
    );
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    actions.dispose();
  }
}
