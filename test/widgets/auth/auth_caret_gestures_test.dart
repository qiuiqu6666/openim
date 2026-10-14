import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/auth/auth_reference_fields.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final compound in [false, true]) {
      for (final password in [false, true]) {
        testWidgets(
            'small caret drag $platform compound=$compound password=$password',
            (tester) async {
          final controller = TextEditingController(text: 'abcdefghijklmno');
          addTearDown(controller.dispose);
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                  body: Center(
                      child: SizedBox(
                          width: 340,
                          child: compound
                              ? AuthCompoundField(
                                  controller: controller,
                                  hint: 'Account',
                                  obscureText: password)
                              : AuthTextField(
                                  controller: controller,
                                  hint: 'Account',
                                  obscureText: password))))));
          await tester.tap(find.byType(TextField));
          await tester.pumpAndSettle();
          final editable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final point = editable.localToGlobal(editable
              .getLocalRectForCaret(const TextPosition(offset: 5))
              .center);
          await tester.tapAt(point);
          await tester.pump();
          final start = controller.selection.baseOffset;
          final gesture = await tester.startGesture(point);
          await gesture.moveBy(const Offset(10, 0));
          await tester.pump(const Duration(milliseconds: 30));
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.baseOffset, greaterThan(start));
          expect(controller.text, 'abcdefghijklmno');
          await gesture.moveBy(const Offset(35, 0));
          await tester.pump(const Duration(milliseconds: 30));
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.baseOffset, greaterThan(start + 1));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(
              tester
                  .widget<TextField>(find.byType(TextField))
                  .selectionControls,
              isNull);
          if (platform == TargetPlatform.android && !password) {
            await tester.longPressAt(point);
            await tester.pumpAndSettle();
            expect(controller.selection.isCollapsed, isFalse);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
