import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_delete_sheet.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final confirm in [false, true]) {
    testWidgets('single delete requires explicit confirmation: $confirm',
        (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            result = await MessageSelectionDeleteSheet.show(context, 1,
                singleMessage: true);
          },
          child: const Text('open'),
        );
      })));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text(confirm ? StrRes.delete : StrRes.cancel));
      await tester.pumpAndSettle();
      expect(result, confirm);
    });
  }
}
