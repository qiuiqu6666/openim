import 'package:flutter/painting.dart';
import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/search/ai_assistant_search.dart';
import 'package:openim_common/openim_common.dart';

import '../../../support/unicode/unicode_samples.dart';

void main() {
  for (final sample in unicodeSamples) {
    test('highlight preserves original ${sample.name}', () {
      final source = 'Before ${sample.text} After ${sample.text}';
      final spans = AiAssistantSearch.highlight(source, sample.text,
          base: const TextStyle(),
          hit: const TextStyle(fontWeight: FontWeight.bold));
      expect(spans.map((span) => span.toPlainText()).join(), source);
      final boundaries = graphemeBoundaries(source);
      var offset = 0;
      for (final span in spans) {
        offset += span.toPlainText().length;
        expect(boundaries, contains(offset));
      }
    });
  }

  test('partial Unicode search highlights entire source graphemes', () {
    for (final cluster in unicodeSamples
        .where((sample) => sample.text.characters.length == 1)
        .map((sample) => sample.text)) {
      // A whitespace-only query is intentionally ignored by search. For a
      // whitespace-base cluster, match its combining scalar instead.
      final needle = String.fromCharCode(cluster.runes.firstWhere(
          (scalar) => String.fromCharCode(scalar).trim().isNotEmpty));
      final spans = AiAssistantSearch.highlight('前$cluster后', needle,
          base: const TextStyle(),
          hit: const TextStyle(fontWeight: FontWeight.bold));
      expect(spans.map((span) => span.toPlainText()).join(), '前$cluster后');
      expect(
          spans
              .where((span) => span.style?.fontWeight == FontWeight.bold)
              .map((span) => span.toPlainText())
              .join(),
          cluster);
    }
  });
}
