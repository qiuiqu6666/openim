import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../conversation_logic.dart';
import 'conversation_edit_controller.dart';

class _ReportedEditFailure implements Exception {
  const _ReportedEditFailure();
}

/// Adapts the page's selection to its existing SDK and organizer operations.
class ConversationEditActions {
  ConversationEditActions({
    required this.logic,
    required this.editor,
    required this.isMounted,
  });

  final ConversationLogic logic;
  final ConversationEditController editor;
  final bool Function() isMounted;

  Future<void> _run(List<ConversationInfo> conversations,
      Future<void> Function(ConversationInfo) action,
      {bool allWhenEmpty = false}) async {
    try {
      await editor.execute(
          conversations: conversations,
          allWhenEmpty: allWhenEmpty,
          action: (info) async {
            if (!isMounted() || !logic.isSessionActive) {
              throw StateError('Session is no longer active');
            }
            await action(info);
          });
    } catch (error) {
      if (error is! _ReportedEditFailure &&
          isMounted() &&
          logic.isSessionActive) {
        IMViews.showToast(error.toString());
      }
    }
  }

  Future<void> markRead(List<ConversationInfo> conversations) =>
      _run(conversations, logic.markConversationRead, allWhenEmpty: true);

  Future<void> archive(List<ConversationInfo> conversations) =>
      _setArchived(conversations, archived: true);

  Future<void> unarchive(List<ConversationInfo> conversations) =>
      _setArchived(conversations, archived: false);

  Future<void> _setArchived(List<ConversationInfo> conversations,
          {required bool archived}) =>
      _run(conversations, (info) async {
        if (!await logic.updateOrganizer(info,
            folderID: logic.folderID(info), archived: archived)) {
          // The organizer already displays its request/conflict error.
          throw const _ReportedEditFailure();
        }
      });

  Future<void> delete(
      BuildContext context, List<ConversationInfo> conversations) async {
    final count = conversations
        .where((info) => editor.selectedIds.contains(info.conversationID))
        .length;
    if (count == 0 || editor.busy) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(zh ? '删除会话' : 'Delete conversations'),
        content: Text(zh
            ? '删除选中的 $count 个会话及聊天记录？'
            : 'Delete the $count selected conversations and their messages?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(StrRes.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(StrRes.delete)),
        ],
      ),
    );
    if (confirmed == true && isMounted() && editor.editing) {
      await _run(conversations, logic.deleteConversation);
    }
  }
}
