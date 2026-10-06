import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/chat_inline_metadata.dart';

void main() {
  testWidgets('same-line runs with different metrics reserve the whole tail',
      (tester) async {
    // CJK fallback fonts can have a different descent than adjacent digits.
    // Mixed sizes reproduce that geometry without platform font dependencies.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: ChatInlineMetadata(
              content: const Text.rich(
                TextSpan(children: [
                  TextSpan(text: '2', style: TextStyle(fontSize: 16)),
                  TextSpan(text: '门', style: TextStyle(fontSize: 24)),
                  TextSpan(text: '20', style: TextStyle(fontSize: 16)),
                ]),
                key: ValueKey('mixed-body'),
              ),
              metadata: const Text('10:02',
                  key: ValueKey('mixed-time'), style: TextStyle(fontSize: 10)),
            ),
          ),
        ),
      ),
    ));
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
      of: find.byKey(const ValueKey('mixed-body')),
      matching: find.byType(RichText),
    ));
    final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4));
    expect(boxes.map((box) => box.bottom).toSet().length, greaterThan(1),
        reason: 'The fixture must contain different descents on the same line');
    final origin = paragraph.localToGlobal(Offset.zero);
    final time = tester.getRect(find.byKey(const ValueKey('mixed-time')));
    for (final box in boxes) {
      final glyph = box.toRect().shift(origin);
      expect(glyph.overlaps(time), isFalse,
          reason: 'Time must not cover any run, including digits after CJK');
      expect(time.left - glyph.right, greaterThanOrEqualTo(6));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed-font tails stay clear around line wrapping boundaries',
      (tester) async {
    for (final width in [90.0, 150.0, 220.0]) {
      for (final scale in [1.0, 1.6]) {
        for (final source in ['2', '2门20', '2门20202020202020', '2门20\n2门20']) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Center(
                    child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: ChatInlineMetadata(
                content: Text.rich(
                    TextSpan(children: [
                      for (final character in source.split(''))
                        TextSpan(
                            text: character,
                            style: TextStyle(
                                fontSize: character == '门' ? 24 : 16)),
                    ]),
                    key: const ValueKey('boundary-body'),
                    textScaler: TextScaler.linear(scale)),
                metadata: const Text('10:02',
                    key: ValueKey('boundary-time'),
                    style: TextStyle(fontSize: 10)),
              ),
            ))),
          ));
          final paragraph =
              tester.renderObject<RenderParagraph>(find.descendant(
            of: find.byKey(const ValueKey('boundary-body')),
            matching: find.byType(RichText),
          ));
          final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: source.length));
          final origin = paragraph.localToGlobal(Offset.zero);
          final time =
              tester.getRect(find.byKey(const ValueKey('boundary-time')));
          for (final box in boxes) {
            final glyph = box.toRect().shift(origin);
            expect(glyph.overlaps(time), isFalse,
                reason: 'width=$width scale=$scale text=$source');
            if (glyph.bottom > time.top && glyph.top < time.bottom) {
              expect(time.left - glyph.right, greaterThanOrEqualTo(6),
                  reason: 'Every glyph on the time line must fit before it');
            }
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
