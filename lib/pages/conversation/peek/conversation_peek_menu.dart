// Adapted from 99chat's conversation_peek_overlay.dart action menu (d7c3c65).
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: use AppTokens and report selection to the preview coordinator.
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'conversation_peek_actions.dart';
import 'conversation_peek_menu_icon.dart';

class _PeekMenuTokens {
  static const radius = 16.0;
  static const iconSize = 20.0;
  static const labelSize = AppTokens.secondaryFontSize;
  static const horizontalPadding = AppTokens.s5;
  static const iconGap = AppTokens.s4;
  static const destructive = Color(0xFFFF3B30);
  static const shadow = Color(0xFF000000);
  static const shadowOpacity = .14;
  static const shadowBlur = 20.0;
  static const shadowOffset = 6.0;
  static const dividerOpacity = .08;
  static const dividerHeight = 1.0;
  static const dividerThickness = .5;
  static const disabledOpacity = .45;
}

/// The shell provides the same screen-dependent width and row padding as 99chat.
/// This widget reports a selection; it does not close routes or invoke the SDK.
class ConversationPeekMenu extends StatelessWidget {
  const ConversationPeekMenu({
    super.key,
    required this.actions,
    required this.menuWidth,
    required this.itemVerticalPadding,
    required this.onSelected,
    this.enabled = true,
  });

  final ConversationPeekActions actions;
  final double menuWidth;
  final double itemVerticalPadding;
  final ValueChanged<ConversationPeekAction> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = actions.menuItems;
    return Container(
      key: const ValueKey('conversation-peek-menu'),
      width: menuWidth,
      decoration: BoxDecoration(
        color: dark ? AppTokens.backgroundDark : AppTokens.surfaceLight,
        borderRadius: BorderRadius.circular(_PeekMenuTokens.radius),
        boxShadow: [
          BoxShadow(
            color: _PeekMenuTokens.shadow
                .withValues(alpha: _PeekMenuTokens.shadowOpacity),
            blurRadius: _PeekMenuTokens.shadowBlur,
            offset: const Offset(0, _PeekMenuTokens.shadowOffset),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (actions.dividerCount != 0 &&
                index == actions.organizationItemCount)
              Divider(
                key: const ValueKey('conversation-peek-menu-divider'),
                height: _PeekMenuTokens.dividerHeight,
                thickness: _PeekMenuTokens.dividerThickness,
                color: _PeekMenuTokens.shadow
                    .withValues(alpha: _PeekMenuTokens.dividerOpacity),
              ),
            _MenuItem(
              action: items[index],
              label: _label(context, items[index]),
              isMuted: actions.isMuted,
              verticalPadding: itemVerticalPadding,
              enabled: enabled && actions.isAvailable,
              onTap: () => onSelected(items[index]),
            ),
          ],
        ],
      ),
    );
  }

  String _label(BuildContext context, ConversationPeekAction action) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return switch (action) {
      ConversationPeekAction.openChat => zh ? '发消息' : 'Send Message',
      ConversationPeekAction.archive => actions.isArchived
          ? (zh ? '取消归档' : 'Unarchive')
          : (zh ? '归档' : 'Archive'),
      ConversationPeekAction.addToFolder => actions.hasFolder
          ? (zh ? '移动至分组' : 'Move to folder')
          : (zh ? '添加至分组' : 'Add to folder'),
      ConversationPeekAction.removeFromFolder =>
        zh ? '移出分组' : 'Remove from folder',
      ConversationPeekAction.togglePin =>
        actions.isPinned ? (zh ? '取消置顶' : 'Unpin') : (zh ? '置顶' : 'Pin'),
      ConversationPeekAction.toggleMute =>
        actions.isMuted ? (zh ? '取消免打扰' : 'Unmute') : (zh ? '静音' : 'Mute'),
      ConversationPeekAction.delete => zh ? '删除' : 'Delete',
    };
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.action,
    required this.label,
    required this.isMuted,
    required this.verticalPadding,
    required this.enabled,
    required this.onTap,
  });

  final ConversationPeekAction action;
  final String label;
  final bool isMuted;
  final double verticalPadding;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = action == ConversationPeekAction.delete
        ? _PeekMenuTokens.destructive
        : AppTokens.textPrimary(dark: dark);
    final color = enabled
        ? baseColor
        : baseColor.withValues(alpha: _PeekMenuTokens.disabledOpacity);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('conversation-peek-action-${action.name}'),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _PeekMenuTokens.horizontalPadding,
              vertical: verticalPadding,
            ),
            child: ExcludeSemantics(
              child: Row(children: [
                ConversationPeekMenuIcon(
                  action: action,
                  size: _PeekMenuTokens.iconSize,
                  color: color,
                  isMuted: isMuted,
                ),
                const SizedBox(width: _PeekMenuTokens.iconGap),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: _PeekMenuTokens.labelSize, color: color)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
