import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/presentation/moments_post_text.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'long text expands locally and retains detail navigation ($dark)',
        (tester) async {
      var opened = 0;
      final text =
          List.filled(20, 'A long post with useful details.').join('\n');
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: SizedBox(
                      width: 320,
                      child: MomentsPostText(
                          text: text, onOpen: () => opened++))))));
      expect(tester.widget<Text>(find.text(text)).maxLines, 6);
      final expand = find.widgetWithText(TextButton, 'Read more');
      expect(tester.getSize(expand).height, greaterThanOrEqualTo(48));
      await tester.tap(expand);
      await tester.pump();
      expect(opened, 0);
      expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
      await tester.tap(find.text(text));
      expect(opened, 1);
      await tester.ensureVisible(find.text('Show less'));
      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(tester.widget<Text>(find.text(text)).maxLines, 6);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('short posts and detail never offer truncation', (tester) async {
    for (final detail in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MomentsPostText(
                  text: detail
                      ? List.filled(10, 'Long text').join('\n')
                      : 'Short post',
                  detail: detail,
                  onOpen: () {}))));
      expect(find.byType(TextButton), findsNothing);
      expect(tester.widget<Text>(find.byType(Text)).maxLines, isNull);
    }
  });
}
