import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../contacts/contacts_logic.dart';
import '../../contacts/presence/contact_presence_policy.dart';
import 'conversation_peek_actions.dart';
import 'conversation_peek_content.dart';
import 'conversation_peek_layout.dart';
import 'conversation_peek_loader.dart';
import 'conversation_peek_menu.dart';
import 'conversation_peek_overlay.dart';
import 'conversation_peek_subtitle.dart';

/// Shared entry point for the single, group, folder and archived feeds.
/// Actions run only after the preview route (including its fade) is removed.
Future<void> showConversationPeek({
  required BuildContext context,
  required ConversationInfo conversation,
  required String displayName,
  required ConversationPeekActions actions,
  required bool Function() isActive,
  ConversationPeekLoader? historyLoader,
}) async {
  if (!context.mounted || !isActive()) return;
  final loader =
      historyLoader ?? ConversationPeekLoader(conversation: conversation);
  ConversationPeekAction? selection;
  Widget? subtitle;
  if (conversation.isGroupChat) {
    subtitle = ConversationPeekSubtitle(
        conversation: conversation, isActive: isActive);
  } else if (FriendDisplayPreferences.showOnlineStatus &&
      Get.isRegistered<ContactsLogic>()) {
    final contacts = Get.find<ContactsLogic>();
    if (!contacts.isClosed) {
      final presence = ContactPresencePolicy.resolve(
        userID: conversation.userID,
        ex: conversation.ex,
        presence: contacts.presence.users[conversation.userID],
      );
      if (presence != null) {
        subtitle = Text(presence.label,
            style: TextStyle(
                color: presence.displayOnline ? AppTokens.accent : null));
      }
    }
  }
  try {
    await ConversationPeekOverlay.show(
      context: context,
      displayName: displayName,
      userID: conversation.userID,
      ex: conversation.ex,
      isSingleChat: conversation.isSingleChat,
      headerSubtitle: subtitle == null
          ? null
          : DefaultTextStyle.merge(
              style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: AppTokens.textSecondary(
                      dark: Theme.of(context).brightness == Brightness.dark)),
              child: subtitle,
            ),
      messageContent:
          ConversationPeekContent(loader: loader, conversation: conversation),
      menuItemCount: actions.itemCount,
      menuDividerCount: actions.dividerCount,
      canOpenChat: () =>
          isActive() &&
          loader.isCurrent &&
          (loader.loaded || loader.messages.isNotEmpty) &&
          (loader.error == null || loader.messages.isNotEmpty),
      onOpenChat: () => selection = ConversationPeekAction.openChat,
      menuBuilder: (menuContext, padding, dismiss) => ConversationPeekMenu(
        actions: actions,
        menuWidth: MediaQuery.sizeOf(menuContext).width *
            ConversationPeekLayout.menuWidthFactor,
        itemVerticalPadding: padding,
        onSelected: (action) {
          if (selection != null || !isActive()) return;
          selection = action;
          dismiss();
        },
      ),
    );
  } finally {
    loader.dispose();
  }
  if (!context.mounted || !isActive() || selection == null) return;
  try {
    await actions.invoke(selection!);
  } catch (error) {
    if (context.mounted && isActive()) {
      IMViews.showToast(Localizations.localeOf(context).languageCode == 'zh'
          ? '操作失败，请重试'
          : 'Unable to complete this action. Please retry.');
    }
  }
}
