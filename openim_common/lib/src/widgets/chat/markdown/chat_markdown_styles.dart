import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../res/app_tokens.dart';

/// Markdown stays within the existing bubble's typography and foreground.
class ChatMarkdownStyles {
  ChatMarkdownStyles._();

  static const imageAspectRatio = 16 / 9;
  static const imageRadius = AppTokens.rSm;
  static const codePadding = EdgeInsets.all(AppTokens.s3);

  static MarkdownStyleSheet of(
    BuildContext context, {
    required TextStyle body,
    TextStyle? link,
    TextScaler? textScaler,
  }) {
    final theme = Theme.of(context);
    final base = (theme.textTheme.bodyMedium ?? const TextStyle()).merge(body);
    final color = base.color ?? theme.colorScheme.onSurface;
    final subtle = color.withValues(alpha: 0.08);
    final border = color.withValues(alpha: 0.22);
    final fontSize = base.fontSize ?? AppTokens.secondaryFontSize;
    final linkStyle = base.merge(link).copyWith(
          color: link?.color ?? theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: link?.color ?? theme.colorScheme.primary,
        );
    TextStyle heading(double factor) => base.copyWith(
          fontSize: fontSize * factor,
          fontWeight: FontWeight.w600,
        );

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      a: linkStyle,
      h1: heading(1.4),
      h2: heading(1.25),
      h3: heading(1.1),
      h4: heading(1),
      h5: heading(1),
      h6: heading(1),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      code: base.copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: [
          if (base.fontFamily != null) base.fontFamily!,
          ...?base.fontFamilyFallback,
        ],
        backgroundColor: subtle,
      ),
      blockquote: base,
      blockquotePadding: const EdgeInsets.all(AppTokens.s3),
      blockquoteDecoration: BoxDecoration(
        color: subtle,
        border: BorderDirectional(start: BorderSide(color: border, width: 3)),
        borderRadius: BorderRadius.circular(AppTokens.s2),
      ),
      blockSpacing: AppTokens.s3,
      listIndent: AppTokens.s7,
      listBullet: base,
      checkbox: base.copyWith(color: linkStyle.color),
      listBulletPadding: const EdgeInsets.only(right: AppTokens.s2),
      tableHead: base.copyWith(fontWeight: FontWeight.w600),
      tableBody: base,
      tableHeadAlign: TextAlign.start,
      // flutter_markdown wraps this in a horizontal scroll view. Its intrinsic
      // columns only measure text; the surrounding bubble remains bounded.
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s3,
        vertical: AppTokens.s2,
      ),
      tableBorder: TableBorder.all(color: border),
      tableCellsDecoration: BoxDecoration(color: subtle),
      tableScrollbarThumbVisibility: false,
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: BoxDecoration(
        color: subtle,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
      ),
      textScaler: textScaler ?? MediaQuery.textScalerOf(context),
    );
  }
}
