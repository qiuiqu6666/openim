import 'package:flutter/material.dart';

import 'chat_toolbox_tokens.dart';

class ChatToolboxTile extends StatelessWidget {
  const ChatToolboxTile({
    super.key,
    required this.id,
    required this.text,
    required this.icon,
    required this.height,
    this.onTap,
    this.width = ChatToolboxTokens.itemWidth,
  });

  final String id;
  final String text;
  final Widget icon;
  final double height;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final labelStyle = ChatToolboxTokens.labelStyle(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      child: Tooltip(
        message: text,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('chat-toolbox-action-$id'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(ChatToolboxTokens.radius),
            child: SizedBox(
              width: width,
              height: height,
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    SizedBox(
                      width: ChatToolboxTokens.iconSlotSize,
                      height: ChatToolboxTokens.iconSlotSize,
                      child: Padding(
                        padding: const EdgeInsets.only(
                            bottom: ChatToolboxTokens.iconBottomMargin),
                        child: DecoratedBox(
                          key: ValueKey('chat-toolbox-icon-$id'),
                          decoration: BoxDecoration(
                            color: ChatToolboxTokens.tileBackground(context),
                            borderRadius:
                                BorderRadius.circular(ChatToolboxTokens.radius),
                          ),
                          child: Center(child: icon),
                        ),
                      ),
                    ),
                    const SizedBox(height: ChatToolboxTokens.labelGap),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: enabled
                          ? labelStyle
                          : labelStyle.copyWith(
                              color: labelStyle.color?.withValues(
                                  alpha: ChatToolboxTokens.disabledOpacity)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
