import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:flutter/services.dart';

import '../../support/unicode/unicode_samples.dart';

void main() {
  for (final sample in unicodeSamples) {
    test('truncate and display ranges never split ${sample.name}', () {
      final clusters = sample.text.characters.toList();
      for (var count = 0; count <= clusters.length + 1; count++) {
        expect(graphemePrefix(sample.text, count), clusters.take(count).join());
        expect(graphemeSuffix(sample.text, count),
            clusters.reversed.take(count).toList().reversed.join());
      }
      final boundaries = graphemeBoundaries(sample.text);
      for (var offset = 0; offset <= sample.text.length; offset++) {
        final previous = boundaries.lastWhere((b) => b <= offset);
        final next = boundaries.firstWhere((b) => b >= offset);
        expect(graphemeBoundaryBefore(sample.text, offset), previous);
        expect(graphemeBoundaryAfter(sample.text, offset), next);
        expect(
            graphemeBoundaryBefore(sample.text, offset, boundaries: boundaries),
            previous);
        expect(
            graphemeBoundaryAfter(sample.text, offset, boundaries: boundaries),
            next);
        final range = graphemeSafeRange(sample.text, offset, offset);
        expect(range, (start: previous, end: next));
      }
      expect(graphemeBoundaryBefore(sample.text, -100), 0);
      expect(graphemeBoundaryAfter(sample.text, sample.text.length + 100),
          sample.text.length);
      expect(utf8.decode(utf8.encode(sample.text)), sample.text);
    });

    test('panel editing at every UTF-16 offset preserves ${sample.name}', () {
      for (final cluster in sample.text.characters) {
        final source = 'X${cluster}Y';
        for (var offset = 1; offset <= cluster.length; offset++) {
          final value = TextEditingValue(
            text: source,
            selection: TextSelection.collapsed(offset: 1 + offset),
          );
          expect(deleteChatTextBackward(value).text, 'XY');
          final inserted = insertChatText(value, 'Z');
          expect(inserted.text, 'X${cluster}ZY');
          expect(inserted.selection.baseOffset, 2 + cluster.length);
        }
        if (cluster.length > 1) {
          final selected = TextEditingValue(
            text: source,
            selection:
                TextSelection(baseOffset: 2, extentOffset: 1 + cluster.length),
          );
          expect(deleteChatTextBackward(selected).text, 'XY');
          expect(insertChatText(selected, 'Z').text, 'XZY');
          final reverse = selected.copyWith(
              selection: TextSelection(
            baseOffset: 1 + cluster.length,
            extentOffset: 2,
          ));
          expect(deleteChatTextBackward(reverse).text, 'XY');
        }
      }
    });
  }

  test(
      'inserted text can merge with the next grapheme without splitting cursor',
      () {
    const first = '\u{1F1E7}';
    const next = '\u{1F1E6}';
    const original = TextEditingValue(
        text: next, selection: TextSelection.collapsed(offset: 0));
    final result = insertChatText(original, first);
    const expected = '$first$next';
    expect(result.text.codeUnits, expected.codeUnits);
    expect(result.selection, TextSelection.collapsed(offset: expected.length));
    expect(
        graphemeBoundaries(result.text), contains(result.selection.baseOffset));
  });

  test('deletion can merge adjacent graphemes without splitting cursor', () {
    const first = '\u{1F1E6}';
    const next = '\u{1F1E7}';
    const original = TextEditingValue(
        text: '${first}X$next', selection: TextSelection.collapsed(offset: 3));
    final result = deleteChatTextBackward(original);
    const expected = '$first$next';
    expect(result.text.codeUnits, expected.codeUnits);
    expect(result.selection, TextSelection.collapsed(offset: expected.length));
    expect(
        graphemeBoundaries(result.text), contains(result.selection.baseOffset));
  });

  test('trim drops whitespace clusters without dropping combining bases', () {
    expect(graphemeTrim('  \u0301  '), ' \u0301');
    expect(graphemeTrim('\n\r\t文字 e\u0301 \u{1F44D}\u{1F3FD}\n '),
        '文字 e\u0301 \u{1F44D}\u{1F3FD}');
    expect(graphemeTrim(' \n\t'), isEmpty);
  });

  test('invalid and absent selections clamp safely', () {
    const source = 'A\u{1F469}\u200D\u{1F4BB}';
    const value = TextEditingValue(text: source);
    expect(insertChatText(value, 'Z').text, '${source}Z');
    expect(deleteChatTextBackward(value).text, 'A');
    final beyond =
        value.copyWith(selection: const TextSelection.collapsed(offset: 999));
    expect(insertChatText(beyond, 'Z').text, '${source}Z');
    expect(deleteChatTextBackward(beyond).text, 'A');
    final atStart =
        value.copyWith(selection: const TextSelection.collapsed(offset: 0));
    expect(deleteChatTextBackward(atStart), same(atStart));
  });

  test('single-line summaries preserve combining whitespace bases', () {
    expect(graphemeCollapseWhitespace('A\n\r\t  B'), 'A B');
    expect(graphemeCollapseWhitespace('A\u00A0\u0301\nB'), 'A\u00A0\u0301 B');
    expect(graphemeCollapseWhitespace(' \u0301 \u{1F469}\u200D\u{1F4BB}'),
        ' \u0301 \u{1F469}\u200D\u{1F4BB}');
  });
}
