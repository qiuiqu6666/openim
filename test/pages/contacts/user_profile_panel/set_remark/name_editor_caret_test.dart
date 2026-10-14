import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/widgets/name_editor_input.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final focused in [false, true]) {
      testWidgets(
          'swipe nickname text away from caret $platform focused=$focused',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = TextEditingController(text: 'abcdefghijklmno');
        addTearDown(controller.dispose);
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => MaterialApp(
                theme: ThemeData(platform: platform),
                home: Scaffold(
                    body: Center(
                        child: SizedBox(
                            width: 360,
                            child: NameEditorInput(
                                controller: controller,
                                maxLength: 30,
                                onSave: () {})))))));
        if (focused) {
          await tester.tap(find.byType(TextField));
          await tester.pumpAndSettle();
        }
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final position = editable.localToGlobal(editable
            .getLocalRectForCaret(const TextPosition(offset: 3))
            .center);
        final gesture = await tester.startGesture(position);
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
        expect(controller.selection.isCollapsed, isTrue);
        expect(
            controller.selection.baseOffset, lessThan(controller.text.length));
        final smallDragOffset = controller.selection.baseOffset;
        await gesture.moveBy(const Offset(35, 0));
        await tester.pump();
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.baseOffset, greaterThan(smallDragOffset));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.text, 'abcdefghijklmno');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
