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
  final selectedFolder = folders?.selectedFolderID;
  final inSelectedFolder =
      selectedFolder != null && logic.folderID(conversation) == selectedFolder;
  final actions = ConversationPeekActions(
    isPinned: conversation.isPinned == true,
    isMuted: logic.isNotDisturb(conversation),
    isArchived: logic.isArchived(conversation),
    onOpenChat: () {
      if (active()) logic.toChat(conversationInfo: current()!);
    },
    onArchive: () => run((info) async {
      await logic.updateOrganizer(info,
          folderID: logic.folderID(info), archived: !logic.isArchived(info));
    }),
    onAddToFolder: folders == null
        ? null
        : () => run((info) => folders.chooseFolder(context, info)),
    onRemoveFromFolder: !inSelectedFolder
        ? null
        : () => run((info) async {
              if (folders!.selectedFolderID == selectedFolder &&
                  logic.folderID(info) == selectedFolder) {
                await folders.removeFromFolder(info);
              }
            }),
    onTogglePin: () =>
        run((info) => logic.setPinned(info, info.isPinned != true)),
    onToggleMute: () =>
        run((info) => logic.setNotDisturb(info, !logic.isNotDisturb(info))),
    // Deletion already owns its confirmation and pending-action guard.
    onDelete: () async {
      if (active()) await onDelete(current()!);
    },
  );
  await showConversationPeek(
    context: context,
    conversation: conversation,
    displayName: logic.getShowName(conversation),
    actions: actions,
    isActive: active,
  );
}
