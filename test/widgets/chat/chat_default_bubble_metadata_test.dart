import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'markdown/support/markdown_fixture.dart';

void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);

  for (final outgoing in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets('default bubble reserves tail gap: $outgoing $brightness',
          (tester) async {
        for (final scale in [1.0, 1.6]) {
          for (final text in ['2门20', 'Hi', '123456789012345678901234567890']) {
            await mountMarkdown(
              tester,
              ChatItemView(
                message: markdownMessage(text, outgoing: outgoing),
                textScaleFactor: scale,
                onTapUserProfile: (_) {},
              ),
              brightness: brightness,
              width: 320,
            );
            // The app's normal chat does not pass a custom text-bubble style.
            final container = tester
                .widget<ChatItemContainer>(find.byType(ChatItemContainer));
            expect(container.textBubbleStyle, isNull);
            final paragraph = tester.renderObject<RenderParagraph>(
              find
                  .descendant(
                    of: find.byType(ChatText),
                    matching: find.byType(RichText),
                  )
                  .first,
            );
            final boxes = paragraph.getBoxesForSelection(TextSelection(
                baseOffset: 0,
                extentOffset: paragraph.text.toPlainText().length));
            final offset = paragraph.localToGlobal(Offset.zero);
            final bottom = boxes.map((box) => box.bottom).reduce(math.max);
            final lastLine =
                boxes.where((box) => (box.bottom - bottom).abs() < 1);
            final right = lastLine.map((box) => box.right).reduce(math.max);
            final time = tester.getRect(find.text('14:08'));
            if (time.top < offset.dy + bottom) {
              expect(time.left - offset.dx - right,
                  greaterThanOrEqualTo(ChatBubbleTokens.metadataHorizontalGap));
            } else {
              final body = tester.getRect(find.byType(ChatText));
              expect(time.top - body.bottom,
                  greaterThanOrEqualTo(ChatBubbleTokens.metadataVerticalGap));
            }
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }
}
