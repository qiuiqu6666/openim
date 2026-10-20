import 'package:openim_common/localization.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_member_action_policy.dart';

/// Shows only the actions already approved by the group permission policy.
Future<ChatMemberAction?> showChatMemberActionSheet(
  BuildContext context, {
  required List<ChatMemberAction> actions,
  required String displayName,
}) {
  if (actions.isEmpty) return Future.value();

  return showModalBottomSheet<ChatMemberAction>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (sheetContext) {
      final textStyle = Styles.ts_0C1C33_17sp;
      final rowHeight = math.max(
        AppTokens.listItemHeight,
        MediaQuery.textScalerOf(sheetContext).scale(textStyle.fontSize!) +
            AppTokens.s5 * 2,
      );
      return Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: AppCopy.format('{#0} 的群成员操作', [displayName]),
        explicitChildNodes: true,
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            child: BottomSheetView(
              isOverlaySheet: true,
              itemHeight: rowHeight,
              textStyle: textStyle,
              onCancel: () => Navigator.of(sheetContext).pop(),
              items: [
                for (final action in actions)
                  SheetItem(
                    label: _label(action),
                    textStyle: action == ChatMemberAction.remove
                        ? textStyle.copyWith(
                            color: Theme.of(sheetContext).colorScheme.error,
                          )
                        : textStyle,
                    onTap: () => Navigator.of(sheetContext).pop(action),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Reuses the app's confirmation dialog for group moderation actions.
Future<bool> confirmChatMemberAction(
  BuildContext context, {
  required ChatMemberAction action,
  required String displayName,
}) async {
  if (action == ChatMemberAction.mention ||
      action == ChatMemberAction.exclusiveRedPacket) {
    return true;
  }

  final title = switch (action) {
    ChatMemberAction.mute => AppCopy.format('确定禁言「{#0}」吗？', [displayName]),
    ChatMemberAction.unmute => AppCopy.format('确定解除「{#0}」的禁言吗？', [displayName]),
    ChatMemberAction.remove => AppCopy.format('确定将「{#0}」移除群聊吗？', [displayName]),
    ChatMemberAction.mention => '',
    ChatMemberAction.exclusiveRedPacket => '',
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => CustomDialog(
      title: title,
      onTapLeft: () => Navigator.of(dialogContext).pop(false),
      onTapRight: () => Navigator.of(dialogContext).pop(true),
    ),
  );
  return confirmed == true;
}

String _label(ChatMemberAction action) => switch (action) {
      ChatMemberAction.mention => AppCopy.text('@对方'),
      ChatMemberAction.exclusiveRedPacket => AppCopy.text('专属红包'),
      ChatMemberAction.mute => '禁言',
      ChatMemberAction.unmute => '解除禁言',
      ChatMemberAction.remove => '移除群聊',
    };
