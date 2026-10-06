import 'package:markdown/markdown.dart' as md;

import '../../text_view.dart';

/// Adds existing chat matches to Markdown's AST without rewriting message data.
/// A dedicated tag avoids nested Markdown links and cannot be injected by a URI.
class ChatMarkdownPatternSyntax extends md.InlineSyntax {
  ChatMarkdownPatternSyntax(this.index, String pattern) : super(pattern);

  static const tag = 'chat-match';
  final int index;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final value = match[0] ?? '';
    if (value.isEmpty) {
      // A caller-provided zero-width expression must still advance the parser.
      parser.advanceBy(1);
      return false;
    }
    parser.addNode(
        md.Element(tag, [md.Text(value)])..attributes['index'] = '$index');
    return true;
  }

  static List<md.InlineSyntax> forPatterns(List<MatchPattern> patterns) {
    final syntaxes = <md.InlineSyntax>[];
    for (var index = 0; index < patterns.length; index++) {
      // Native GFM autolinks preserve full hostnames and trim punctuation.
      // They still use the supplied callbacks through Markdown's onTapLink.
      if (patterns[index].type == PatternType.url ||
          patterns[index].type == PatternType.email) {
        continue;
      }
      final pattern = patternFor(patterns[index]);
      if (pattern == null || pattern.isEmpty) continue;
      // Malformed optional custom patterns must not break a message bubble.
      try {
        syntaxes.add(ChatMarkdownPatternSyntax(index, pattern));
      } on FormatException {
        continue;
      }
    }
    return syntaxes;
  }

  static String? patternFor(MatchPattern pattern) => switch (pattern.type) {
        PatternType.email => regexEmail,
        PatternType.url => regexUrl,
        PatternType.mobile => _withinText(regexMobile),
        PatternType.tel => _withinText(regexTel),
        _ => pattern.pattern,
      };

  static String _withinText(String pattern) {
    final content = pattern.replaceFirst(RegExp(r'^\^'), '').replaceFirst(
          RegExp(r'\$$'),
          '',
        );
    // A number may occur inside a paragraph or emphasis. Keep the original
    // number structure, but do not link a suffix inside an account/long ID.
    return r'(?<![A-Za-z0-9_@])(?:' + content + r')(?![A-Za-z0-9_])';
  }

  static String target(String text, PatternType type) => switch (type) {
        PatternType.url => text.startsWith('http') ? text : 'http://$text',
        PatternType.email => text.startsWith('mailto:') ? text : 'mailto:$text',
        PatternType.mobile ||
        PatternType.tel =>
          text.startsWith('tel:') ? text : 'tel:$text',
        _ => text,
      };

  static bool isSafeLink(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    return switch (uri.scheme.toLowerCase()) {
      'http' || 'https' => uri.host.isNotEmpty,
      'mailto' || 'tel' => uri.path.isNotEmpty,
      _ => false,
    };
  }
}
