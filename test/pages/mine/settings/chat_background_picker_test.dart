import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/appearance/chat_background/chat_background_picker.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('selection waits for Done and Cancel discards it dark=$dark',
        (tester) async {
      final saved = <String?>[];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => ChatBackgroundPicker(
                              onSave: (value) async => saved.add(value)))),
                  child: const Text('Open'),
                ))),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.tap(find.bySemanticsLabel('Desert Mesas'));
      await tester.pump();
      expect(saved, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Desert Mesas'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved, ['asset:assets/images/chat_backgrounds/desert.webp']);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
