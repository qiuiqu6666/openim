// Adapted from 99chat's conversation_peek_actions.dart (d7c3c65).
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: expose supported OpenIM actions and separate selection from execution.
import 'dart:async';

import 'package:flutter/foundation.dart';

enum ConversationPeekAction {
  openChat,
  archive,
  addToFolder,
  removeFromFolder,
  togglePin,
  toggleMute,
  delete,
}

typedef ConversationPeekCallback = FutureOr<void> Function();

/// A snapshot of real conversation state and the operations the caller supports.
/// Null callbacks are omitted from the menu; this model never synthesizes state.
class ConversationPeekActions {
  const ConversationPeekActions({
    required this.onOpenChat,
    this.onArchive,
    this.onAddToFolder,
    this.onRemoveFromFolder,
    this.onTogglePin,
    this.onToggleMute,
    this.onDelete,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.isOfficialAccount = false,
  });

  final VoidCallback onOpenChat;
  final Future<void> Function()? onArchive;
  final Future<void> Function()? onAddToFolder;
  final Future<void> Function()? onRemoveFromFolder;
  final Future<void> Function()? onTogglePin;
  final Future<void> Function()? onToggleMute;
  final Future<void> Function()? onDelete;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool isOfficialAccount;

  List<ConversationPeekAction> get menuItems {
    if (isOfficialAccount) {
      return [if (onDelete != null) ConversationPeekAction.delete];
    }
    return [
      if (onArchive != null) ConversationPeekAction.archive,
      if (onAddToFolder != null) ConversationPeekAction.addToFolder,
      if (onRemoveFromFolder != null) ConversationPeekAction.removeFromFolder,
      if (onTogglePin != null) ConversationPeekAction.togglePin,
      if (onToggleMute != null) ConversationPeekAction.toggleMute,
      if (onDelete != null) ConversationPeekAction.delete,
    ];
  }

  int get organizationItemCount => isOfficialAccount
      ? 0
      : (onArchive == null ? 0 : 1) +
          (onAddToFolder == null ? 0 : 1) +
          (onRemoveFromFolder == null ? 0 : 1);
  int get itemCount => menuItems.length;
  int get dividerCount =>
      organizationItemCount > 0 && itemCount > organizationItemCount ? 1 : 0;

  ConversationPeekCallback? callbackFor(ConversationPeekAction action) =>
      switch (action) {
        ConversationPeekAction.openChat => onOpenChat,
        ConversationPeekAction.archive => onArchive,
        ConversationPeekAction.addToFolder => onAddToFolder,
        ConversationPeekAction.removeFromFolder => onRemoveFromFolder,
        ConversationPeekAction.togglePin => onTogglePin,
        ConversationPeekAction.toggleMute => onToggleMute,
        ConversationPeekAction.delete => onDelete,
      };

  /// The coordinator calls this after dismissing the preview route.
  Future<void> invoke(ConversationPeekAction action) {
    final callback = callbackFor(action);
    return callback == null
        ? Future<void>.value()
        : Future<void>.sync(callback);
  }
}
