import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../pop_button.dart';
import 'chat_message_menu_icon.dart';
import 'chat_message_menu_tokens.dart';

/// The native 99chat action grid. SDK policy and callbacks stay with the caller.
class ChatMessageMenuPanel extends StatelessWidget {
  const ChatMessageMenuPanel({
    super.key,
    required this.menus,
    required this.onSelected,
  });

  final List<PopMenuInfo> menus;
  final ValueChanged<PopMenuInfo> onSelected;

  static int labelLines(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(ChatMessageMenuTokens.labelSize) >
              ChatMessageMenuTokens.labelSize * 1.3
          ? 3
          : 1;

  static double resolvedCellHeight(
      BuildContext context, List<PopMenuInfo> menus) {
    var height = ChatMessageMenuTokens.cellHeight;
    for (final menu in menus) {
      final painter = TextPainter(
        text: TextSpan(text: menu.text, style: _labelStyle(context)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: labelLines(context),
        ellipsis: '…',
      )..layout(maxWidth: ChatMessageMenuTokens.cellWidth);
      height = math.max(
          height,
          painter.height +
              ChatMessageMenuTokens.iconSize +
              ChatMessageMenuTokens.iconGap +
              ChatMessageMenuTokens.verticalPadding);
      painter.dispose();
    }
    return height;
  }

  static double preferredHeight(
          BuildContext context, List<PopMenuInfo> menus) =>
      resolvedCellHeight(context, menus) *
          (menus.length <= ChatMessageMenuTokens.columns ? 1 : 2) +
      ChatMessageMenuTokens.verticalPadding * 2;

  static TextStyle _labelStyle(BuildContext context) =>
      (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
        fontSize: ChatMessageMenuTokens.labelSize,
        height: ChatMessageMenuTokens.labelHeight,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        decoration: TextDecoration.none,
        color: ChatMessageMenuTokens.foreground,
      );

  @override
  Widget build(BuildContext context) {
    final cellHeight = resolvedCellHeight(context, menus);
    final rows = menus.length <= ChatMessageMenuTokens.columns ? 1 : 2;
    return Material(
      key: const ValueKey('chat-message-menu-panel'),
      color: ChatMessageMenuTokens.background,
      borderRadius: BorderRadius.circular(ChatMessageMenuTokens.radius),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ChatMessageMenuTokens.horizontalPadding,
              vertical: ChatMessageMenuTokens.verticalPadding),
          child: SizedBox(
            height: cellHeight * rows,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  for (var start = 0;
                      start < menus.length;
                      start += ChatMessageMenuTokens.itemsPerPage)
                    SizedBox(
                      width: ChatMessageMenuTokens.columns *
                          ChatMessageMenuTokens.cellWidth,
                      child: Column(
                        children: [
                          for (var row = 0; row < rows; row++)
                            Row(children: [
                              for (var column = 0;
                                  column < ChatMessageMenuTokens.columns;
                                  column++)
                                _cell(
                                    context,
                                    start +
                                        row * ChatMessageMenuTokens.columns +
                                        column,
                                    cellHeight),
                            ]),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int index, double height) {
    if (index >= menus.length) {
      return SizedBox(width: ChatMessageMenuTokens.cellWidth, height: height);
    }
    final menu = menus[index];
    final action = menu.id ?? '';
    final color = action == 'delete'
        ? ChatMessageMenuTokens.destructive
        : ChatMessageMenuTokens.foreground;
    final icon = menu.iconWidget ??
        (ChatMessageMenuIcon.supports(action)
            ? ChatMessageMenuIcon(action: action, color: color)
            : menu.icon != null
                ? Image.asset(menu.icon!,
                    color: color,
                    width: ChatMessageMenuTokens.iconSize,
                    height: ChatMessageMenuTokens.iconSize)
                : Icon(Icons.more_horiz_rounded,
                    color: color, size: ChatMessageMenuTokens.iconSize));
    return SizedBox(
      width: ChatMessageMenuTokens.cellWidth,
      height: height,
      child: Tooltip(
        message: menu.text,
        child: InkWell(
          key: ValueKey('chat-message-menu-action-${menu.id ?? index}'),
          onTap: menu.onTap == null ? null : () => onSelected(menu),
          child: Semantics(
            button: true,
            enabled: menu.onTap != null,
            label: menu.text,
            excludeSemantics: true,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                    dimension: ChatMessageMenuTokens.iconSize, child: icon),
                const SizedBox(height: ChatMessageMenuTokens.iconGap),
                Text(menu.text,
                    maxLines: labelLines(context),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _labelStyle(context).copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
