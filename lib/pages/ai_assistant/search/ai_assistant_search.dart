import 'package:flutter/painting.dart';
import 'package:characters/characters.dart';
import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';
import 'package:openim_common/openim_common.dart';

class AiAssistantSearch {
  AiAssistantSearch._();

  static String normalize(String raw) {
    return graphemeTrim(raw).toLowerCase();
  }

  static String haystack(AiAssistantMessage message) {
    return normalize(_plainParts(message).join(' '));
  }

  static String copyText(AiAssistantMessage message) {
    return _plainParts(message).join('\n');
  }

  static List<String> _plainParts(AiAssistantMessage message) {
    if (message.outputKind == AiAssistantOutputKind.thinking) {
      return const <String>[];
    }
    final parts = <String>[];
    final text = message.text ?? '';
    if (graphemeTrim(text).isNotEmpty) {
      parts.add(text);
    }
    for (final file in message.files) {
      if (file.name.isNotEmpty) {
        parts.add(file.name);
      }
    }
    for (final card in message.cards) {
      if (card.name.isNotEmpty) {
        parts.add(card.name);
      }
    }
    final summary = message.summary;
    if (summary != null) {
      parts.add(summary.title);
      parts.add(summary.meta);
      parts.addAll(summary.items);
      parts.add(summary.footer);
    }
    final analysis = message.analysis;
    if (analysis != null) {
      parts.add(analysis.fileName);
      parts.addAll(analysis.bullets);
    }
    final code = message.code;
    if (code != null) {
      if (code.language.isNotEmpty) {
        parts.add(code.language);
      }
      if (code.source.isNotEmpty) {
        parts.add(code.source);
      }
    }
    return parts;
  }

  static bool matches(AiAssistantMessage message, String query) {
    final needle = normalize(query);
    if (needle.isEmpty) {
      return false;
    }
    return haystack(message).contains(needle);
  }

  static List<int> matchIndexes(
    List<AiAssistantMessage> messages,
    String query,
  ) {
    final indexes = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (matches(messages[i], query)) {
        indexes.add(i);
      }
    }
    return indexes;
  }

  static List<InlineSpan> highlight(
    String source,
    String query, {
    required TextStyle base,
    required TextStyle hit,
  }) {
    final needle = normalize(query);
    if (needle.isEmpty || source.isEmpty) {
      return <InlineSpan>[TextSpan(text: source, style: base)];
    }
    // Search folding is temporary. Map folded positions back to complete
    // source graphemes before assigning styles, including partial matches.
    final folded = StringBuffer();
    final sourceOffsets = <int, int>{0: 0};
    var sourceOffset = 0;
    var foldedOffset = 0;
    for (final character in source.characters) {
      final lower = character.toLowerCase();
      folded.write(lower);
      sourceOffset += character.length;
      foldedOffset += lower.length;
      sourceOffsets[foldedOffset] = sourceOffset;
    }
    final lower = folded.toString();
    final boundaries = sourceOffsets.keys.toList(growable: false);
    final spans = <InlineSpan>[];
    var start = 0;
    var from = 0;
    while (true) {
      final index = lower.indexOf(needle, from);
      if (index < 0) {
        if (start < source.length) {
          spans.add(TextSpan(text: source.substring(start), style: base));
        }
        break;
      }
      final matchStart = sourceOffsets[
          graphemeBoundaryBefore(lower, index, boundaries: boundaries)]!;
      final matchEnd = sourceOffsets[graphemeBoundaryAfter(
          lower, index + needle.length,
          boundaries: boundaries)]!;
      from = index + needle.length;
      if (matchStart < start) continue;
      if (matchStart > start) {
        spans.add(
            TextSpan(text: source.substring(start, matchStart), style: base));
      }
      spans.add(
        TextSpan(
          text: source.substring(matchStart, matchEnd),
          style: hit,
        ),
      );
      start = matchEnd;
    }
    if (spans.isEmpty) {
      return <InlineSpan>[TextSpan(text: source, style: base)];
    }
    return spans;
  }
}
