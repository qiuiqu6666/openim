import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/widgets/message_action_confirmation_sheet.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final choice in ['confirm', 'cancel', 'dismiss']) {
      testWidgets('recall confirmation $choice in $brightness', (tester) async {
        bool? result;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Builder(
              builder: (context) => TextButton(
                    child: const Text('open'),
                    onPressed: () async {
                      result = await MessageActionConfirmationSheet.show(
                          context,
                          title: '确定撤回这条消息？',
                          action: StrRes.menuRevoke,
                          sheetKey: const ValueKey(
                              'message-revoke-confirmation-sheet'));
                    },
                  )),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('确定撤回这条消息？'), findsOneWidget);
        expect(result, isNull);
        if (choice == 'dismiss') {
          await tester.tapAt(const Offset(10, 10));
        } else {
          await tester.tap(find
              .text(choice == 'confirm' ? StrRes.menuRevoke : StrRes.cancel));
        }
        await tester.pumpAndSettle();
        expect(result, choice == 'confirm');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
