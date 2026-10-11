import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/markdown/chat_markdown_styles.dart';
import 'package:openim_common/src/res/typography/chat_message_typography.dart';

// Independent transcription of production 99chat's
// MessageBubbleTextColor.messageBodyBaseStyle (native platforms).
TextStyle _referenceStyle(TargetPlatform platform, bool dark) => TextStyle(
      inherit: false,
      fontFamily:
          platform == TargetPlatform.windows ? 'Microsoft YaHei UI' : null,
      fontFamilyFallback: platform == TargetPlatform.windows
          ? const ['Microsoft YaHei', 'Segoe UI']
          : null,
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      color: dark ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E),
    );

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows
  ]) {
    for (final dark in [false, true]) {
      testWidgets('body pixels and line boxes match 99chat: $platform $dark',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        final reference = _referenceStyle(platform, dark);
        const text = '聊天正文 Hello 123\n第二行：组合表情 ❤️\n字号和行距一致';
        for (final scale in [1.0, 1.8]) {
          Future<(Size, List<ui.TextBox>, Uint8List)> render(
              Widget body) async {
            await tester.pumpWidget(MaterialApp(
              theme: ThemeData(
                platform: platform,
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: 'UnrelatedPageFont',
              ),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: DefaultTextStyle(
                  style: const TextStyle(
                      fontSize: 30,
                      height: 3,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      wordSpacing: 12,
                      fontFamily: 'UnrelatedPageFont'),
                  child: Center(
                      child: SizedBox(
                    width: 220,
                    child: RepaintBoundary(
                        key: key,
                        child: ColoredBox(
                          color: dark
                              ? const Color(0xFF1B1D22)
                              : const Color(0xFFFFFFFF),
                          child: body,
                        )),
                  )),
                ),
              ),
            ));
            await tester.pumpAndSettle();
            final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                    of: find.byKey(key), matching: find.byType(RichText)));
            final boxes = paragraph.getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: text.length));
            final boundary =
                tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
            final bytes = await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
              image.dispose();
              return data!.buffer.asUint8List();
            });
            expect(tester.takeException(), isNull);
            return (paragraph.size, boxes, bytes!);
          }

          final expected = await render(Text(text, style: reference));
          final actual =
              await render(const ChatText(text: text, maximumWidth: 220));
          expect(actual.$1, expected.$1);
          expect(actual.$2.map((b) => b.toRect()).toList(),
              expected.$2.map((b) => b.toRect()).toList());
          expect(actual.$3, orderedEquals(expected.$3));

          final formatted =
              await render(const ChatFormattedText(text: text, entities: []));
          expect(formatted.$1, expected.$1);
          expect(formatted.$3, orderedEquals(expected.$3));
        }
      });
    }
  }

  testWidgets('Markdown and links retain the isolated message typography',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      final body = chatMessageTextStyle(context);
      final styles = ChatMarkdownStyles.of(context, body: body);
      expect(styles.p?.inherit, isFalse);
      expect(styles.p?.fontSize, 16);
      expect(styles.p?.height, 1.3);
      expect(styles.p?.letterSpacing, isNull);
      expect(styles.p?.wordSpacing, isNull);
      expect(styles.a?.height, 1.3);
      return const SizedBox.shrink();
    })));
  });
}
