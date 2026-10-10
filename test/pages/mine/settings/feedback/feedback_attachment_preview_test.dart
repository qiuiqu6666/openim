import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/feedback/widgets/feedback_attachment_preview.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets(
      'invalid screenshot placeholder follows live light and dark theme',
      (tester) async {
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    final invalidImage = Uint8List.fromList([0, 1, 2]);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: dark,
      builder: (_, isDark, __) => MaterialApp(
        theme:
            ThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
        home: Scaffold(
          body: SizedBox.square(
            dimension: 100,
            child: FeedbackAttachmentPreview(bytes: invalidImage),
          ),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    for (final isDark in [false, true, false]) {
      dark.value = isDark;
      await tester.pumpAndSettle();
      final placeholder = tester.widget<ColoredBox>(find.descendant(
        of: find.byType(FeedbackAttachmentPreview),
        matching: find.byType(ColoredBox),
      ));
      final icon =
          tester.widget<Icon>(find.byIcon(Icons.broken_image_outlined));
      expect(placeholder.color, AppTokens.surfaceAlt(dark: isDark));
      expect(icon.color, AppTokens.textSecondary(dark: isDark));
      final fg = icon.color!.computeLuminance();
      final bg = placeholder.color.computeLuminance();
      final contrast =
          fg > bg ? (fg + .05) / (bg + .05) : (bg + .05) / (fg + .05);
      expect(contrast, greaterThan(3));
      expect(tester.takeException(), isNull);
    }
  });
}
