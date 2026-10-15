import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat/history_search/chat_history_search_tokens.dart';

/// Shared geometry for search results and their loading placeholders.
abstract final class GlobalSearchResultTokens {
  static const avatarSize = ChatHistorySearchTokens.avatarSize;
  static const rowMinHeight = ChatHistorySearchTokens.rowMinHeight;
  static const horizontalPadding = AppTokens.s5;
  static const avatarTextGap = ChatHistorySearchTokens.avatarTextGap;
  static const verticalPadding = ChatHistorySearchTokens.rowVerticalPadding;
  static const textGap = ChatHistorySearchTokens.textGap;
  static const dividerInset = horizontalPadding + avatarSize + avatarTextGap;
  static const dividerThickness = ChatHistorySearchTokens.moreDividerThickness;
  static const sectionPadding = EdgeInsets.fromLTRB(
      horizontalPadding, AppTokens.s4, horizontalPadding, AppTokens.s2);

  static Color secondaryColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color background(BuildContext context) =>
      ChatHistorySearchTokens.pageBackground(
          dark: Theme.of(context).brightness == Brightness.dark);

  static TextStyle titleStyle(BuildContext context) =>
      (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: AppTokens.textPrimary(
            dark: Theme.of(context).brightness == Brightness.dark),
        fontSize: ChatHistorySearchTokens.titleFontSize,
        height: ChatHistorySearchTokens.titleHeight,
        fontWeight: FontWeight.w500,
      );

  static TextStyle subtitleStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        color: secondaryColor(context),
        fontSize: ChatHistorySearchTokens.previewFontSize,
        height: ChatHistorySearchTokens.previewHeight,
        fontWeight: FontWeight.w400,
      );

  static TextStyle metadataStyle(BuildContext context) =>
      (Theme.of(context).textTheme.labelMedium ?? const TextStyle()).copyWith(
        color: secondaryColor(context),
        fontSize: ChatHistorySearchTokens.timeFontSize,
        height: ChatHistorySearchTokens.titleHeight,
        fontWeight: FontWeight.w500,
      );
}
