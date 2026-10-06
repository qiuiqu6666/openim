// Adapted from 99chat's conversation.dart editing selection control.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: use current AppTokens; the owning row handles selection gestures.
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'conversation_edit_tokens.dart';

class ConversationSelectionIndicator extends StatelessWidget {
  const ConversationSelectionIndicator({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      selected: selected,
      child: Container(
        width: ConversationEditTokens.selectionSize,
        height: ConversationEditTokens.selectionSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppTokens.accent : null,
          border: Border.all(
            color: selected
                ? AppTokens.accent
                : AppTokens.textSecondary(dark: dark),
            width: ConversationEditTokens.selectionBorderWidth,
          ),
        ),
        child: selected
            ? const ExcludeSemantics(
                child: Icon(
                  Icons.check,
                  size: ConversationEditTokens.checkSize,
                  color: AppTokens.onAccent,
                ),
              )
            : null,
      ),
    );
  }
}
