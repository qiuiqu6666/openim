import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/scrolling/chat_message_highlight.dart';

void main() {
  testWidgets('bubble feedback fades without rebuilding its media child',
      (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    var mediaBuilds = 0;
    final media = Builder(builder: (_) {
      mediaBuilds++;
      return const SizedBox(width: 160, height: 100);
    });
    await tester.pumpWidget(MaterialApp(
        home: Center(
      child: ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (_, value, __) => ChatMessageHighlight(
          active: value,
          color: Colors.blue.withValues(alpha: .1),
          fadeDuration: const Duration(milliseconds: 250),
          child: Builder(
              builder: (context) =>
                  ChatMessageHighlight.wrap(context, media, 12)),
        ),
      ),
    )));
    double opacity() => (tester
            .widget<DecoratedBox>(find
                .descendant(
                    of: find.byType(IgnorePointer),
                    matching: find.byType(DecoratedBox))
                .last)
            .decoration as BoxDecoration)
        .color!
        .a;
    expect(opacity(), closeTo(.1, .001));
    final builds = mediaBuilds;
    active.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(opacity(), inExclusiveRange(0, .1));
    await tester.pump(const Duration(milliseconds: 125));
    expect(opacity(), 0);
    expect(mediaBuilds, builds);
  });
}
