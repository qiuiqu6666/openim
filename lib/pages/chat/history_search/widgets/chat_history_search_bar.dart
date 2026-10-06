import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_history_search_strings.dart';
import '../chat_history_search_tokens.dart';

/// The conversation search field and cancel action used by 99chat.
///
/// The shared SearchBox lays out its icons outside the field, so this local
/// control keeps the reference field's native prefix/suffix insets instead.
class ChatHistorySearchBar extends StatelessWidget {
  const ChatHistorySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCancel,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primaryText = AppTokens.textPrimary(dark: dark);
    final secondaryText = AppTokens.textSecondary(dark: dark);
    final fieldHeight = (MediaQuery.textScalerOf(context)
                    .scale(ChatHistorySearchTokens.searchFontSize) *
                ChatHistorySearchTokens.searchLineHeight +
            2 * ChatHistorySearchTokens.searchVerticalPadding)
        .clamp(ChatHistorySearchTokens.searchMinHeight, double.infinity);
    final style = TextStyle(
      color: primaryText,
      fontSize: ChatHistorySearchTokens.searchFontSize,
      height: ChatHistorySearchTokens.searchLineHeight,
    );
    final cancelLabel = chatHistorySearchText(context, 'cancel');

    return ColoredBox(
      color: ChatHistorySearchTokens.pageBackground(dark: dark),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ChatHistorySearchTokens.horizontalPadding,
          ChatHistorySearchTokens.searchTopPadding,
          ChatHistorySearchTokens.horizontalPadding,
          ChatHistorySearchTokens.searchBottomPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: Theme(
                data: theme.copyWith(
                  textSelectionTheme: theme.textSelectionTheme.copyWith(
                    cursorColor: AppTokens.accent,
                    selectionColor: AppTokens.accent.withValues(
                      alpha: ChatHistorySearchTokens.searchSelectionOpacity,
                    ),
                    selectionHandleColor: AppTokens.accent,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ChatHistorySearchTokens.searchFill(dark: dark),
                    borderRadius: BorderRadius.circular(
                      ChatHistorySearchTokens.searchRadius,
                    ),
                  ),
                  child: SizedBox(
                    height: fieldHeight,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => TextField(
                        key: const ValueKey('chat-history-search-input'),
                        controller: controller,
                        autofocus: autofocus,
                        textInputAction: TextInputAction.search,
                        textAlignVertical: TextAlignVertical.center,
                        style: style,
                        cursorColor: AppTokens.accent,
                        onChanged: (value) => onChanged(value.trim()),
                        onSubmitted: (value) => onSubmitted(value.trim()),
                        decoration: InputDecoration(
                          hintText: chatHistorySearchText(context, 'search'),
                          hintStyle: style.copyWith(color: secondaryText),
                          prefixIcon: Icon(
                            Icons.search,
                            size: ChatHistorySearchTokens.searchIconSize,
                            color: secondaryText,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth:
                                ChatHistorySearchTokens.searchIconMinWidth,
                            minHeight:
                                ChatHistorySearchTokens.searchIconMinHeight,
                          ),
                          suffixIcon: value.text.trim().isNotEmpty
                              ? IconButton(
                                  key: const ValueKey(
                                      'chat-history-search-clear'),
                                  tooltip:
                                      chatHistorySearchText(context, 'clear'),
                                  onPressed: () {
                                    controller.clear();
                                    onChanged('');
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: ChatHistorySearchTokens
                                        .searchIconMinWidth,
                                    minHeight: ChatHistorySearchTokens
                                        .searchIconMinHeight,
                                  ),
                                  icon: Icon(
                                    Icons.cancel,
                                    size:
                                        ChatHistorySearchTokens.searchIconSize,
                                    color: secondaryText,
                                  ),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth:
                                ChatHistorySearchTokens.searchIconMinWidth,
                            minHeight:
                                ChatHistorySearchTokens.searchIconMinHeight,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical:
                                ChatHistorySearchTokens.searchVerticalPadding,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: ChatHistorySearchTokens.cancelGap),
            Semantics(
              button: true,
              label: cancelLabel,
              onTap: onCancel,
              child: ExcludeSemantics(
                child: GestureDetector(
                  key: const ValueKey('chat-history-search-cancel'),
                  onTap: onCancel,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppTokens.s3),
                    child: Text(
                      cancelLabel,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: ChatHistorySearchTokens.cancelFontSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
