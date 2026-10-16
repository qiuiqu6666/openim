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
    this.focusNode,
    this.hintText,
    this.cancelColor,
    this.onTap,
    this.readOnly = false,
    this.cancelProgress = 1,
    this.fieldKey,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? hintText;
  final Color? cancelColor;
  final VoidCallback? onTap;
  final bool readOnly;
  final double cancelProgress;
  final Key? fieldKey;

  static double fieldHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context)
                      .scale(ChatHistorySearchTokens.searchFontSize) *
                  ChatHistorySearchTokens.searchLineHeight +
              2 * ChatHistorySearchTokens.searchVerticalPadding)
          .clamp(ChatHistorySearchTokens.searchMinHeight, double.infinity);

  static double height(BuildContext context) =>
      fieldHeight(context) +
      ChatHistorySearchTokens.searchTopPadding +
      ChatHistorySearchTokens.searchBottomPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primaryText = AppTokens.textPrimary(dark: dark);
    final secondaryText = AppTokens.textSecondary(dark: dark);
    final inputHeight = fieldHeight(context);
    final reveal = cancelProgress.clamp(0.0, 1.0);
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
                  key: fieldKey,
                  decoration: BoxDecoration(
                    color: ChatHistorySearchTokens.searchFill(dark: dark),
                    borderRadius: BorderRadius.circular(
                      ChatHistorySearchTokens.searchRadius,
                    ),
                  ),
                  child: SizedBox(
                    height: inputHeight,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        final centerHint = readOnly && value.text.isEmpty;
                        final label = hintText ??
                            chatHistorySearchText(context, 'search');
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            TextField(
                              key: const ValueKey('chat-history-search-input'),
                              controller: controller,
                              focusNode: focusNode,
                              autofocus: autofocus,
                              onTap: onTap,
                              readOnly: readOnly,
                              canRequestFocus: !readOnly,
                              showCursor: !readOnly,
                              enableInteractiveSelection: !readOnly,
                              textInputAction: TextInputAction.search,
                              textAlignVertical: TextAlignVertical.center,
                              style: style,
                              cursorColor: AppTokens.accent,
                              onChanged: (value) =>
                                  onChanged(graphemeTrim(value)),
                              onSubmitted: (value) =>
                                  onSubmitted(graphemeTrim(value)),
                              decoration: InputDecoration(
                                hintText: centerHint ? null : label,
                                hintStyle: style.copyWith(color: secondaryText),
                                prefixIcon: centerHint
                                    ? null
                                    : Icon(
                                        Icons.search,
                                        size: ChatHistorySearchTokens
                                            .searchIconSize,
                                        color: secondaryText,
                                      ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: ChatHistorySearchTokens
                                      .searchIconMinWidth,
                                  minHeight: ChatHistorySearchTokens
                                      .searchIconMinHeight,
                                ),
                                suffixIcon: graphemeTrim(value.text).isNotEmpty
                                    ? IconButton(
                                        key: const ValueKey(
                                            'chat-history-search-clear'),
                                        tooltip: chatHistorySearchText(
                                            context, 'clear'),
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
                                          size: ChatHistorySearchTokens
                                              .searchIconSize,
                                          color: secondaryText,
                                        ),
                                      )
                                    : null,
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: ChatHistorySearchTokens
                                      .searchIconMinWidth,
                                  minHeight: ChatHistorySearchTokens
                                      .searchIconMinHeight,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: ChatHistorySearchTokens
                                      .searchVerticalPadding,
                                ),
                              ),
                            ),
                            if (centerHint)
                              IgnorePointer(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search,
                                      size: ChatHistorySearchTokens
                                          .searchIconSize,
                                      color: secondaryText,
                                    ),
                                    const SizedBox(
                                      width:
                                          ChatHistorySearchTokens.searchHintGap,
                                    ),
                                    Flexible(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: style.copyWith(
                                            color: secondaryText),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: reveal,
                child: Opacity(
                  opacity: reveal,
                  child: IgnorePointer(
                    ignoring: reveal == 0,
                    child: ExcludeSemantics(
                      excluding: reveal == 0,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                            width: ChatHistorySearchTokens.cancelGap),
                        Semantics(
                          button: true,
                          label: cancelLabel,
                          onTap: onCancel,
                          child: ExcludeSemantics(
                            child: GestureDetector(
                              key: const ValueKey('chat-history-search-cancel'),
                              onTap: onCancel,
                              behavior: HitTestBehavior.opaque,
                              child: SizedBox(
                                height: inputHeight,
                                child: Center(
                                    child: Text(
                                  cancelLabel,
                                  style: TextStyle(
                                    color: cancelColor ?? primaryText,
                                    fontSize:
                                        ChatHistorySearchTokens.cancelFontSize,
                                    height: ChatHistorySearchTokens
                                        .searchLineHeight,
                                  ),
                                )),
                              ),
                            ),
                          ),
                        ),
                      ]),
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
