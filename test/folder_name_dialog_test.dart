import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/folder_name_dialog.dart';

void main() {
  for (final save in [false, true]) {
    testWidgets(
        'folder dialog closes cleanly when ${save ? 'saved' : 'cancelled'}',
        (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const FolderNameDialog(),
                );
              },
              child: const Text('打开'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      if (save) {
        await tester.enterText(find.byType(TextField), '测试分组');
      }
      await tester.tap(find.text(save ? '保存' : '取消'));
      await tester.pumpAndSettle();

      expect(result, save ? '测试分组' : null);
      expect(tester.takeException(), isNull);
    });
  }
}
