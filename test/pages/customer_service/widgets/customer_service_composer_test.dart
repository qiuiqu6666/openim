import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/widgets/customer_service_composer.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('support reuses chat input appearance in $brightness',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var sends = 0;
      var attachments = 0;
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return CustomerServiceComposer(
              controller: controller,
              enabled: enabled,
              onSend: () => sends++,
              onAttach: () => attachments++,
            );
          }),
        ),
      ));
      final input = find.byKey(const ValueKey('customer-service-input'));
      final send = find.byKey(const ValueKey('customer-service-send'));
      final attach = find.byKey(const ValueKey('customer-service-attach'));
      final field = tester.widget<TextField>(input);
      final context = tester.element(input);
      expect(field.style, chatComposerTextStyle(context));
      expect(field.decoration!.fillColor, chatComposerInputFill(context));
      expect(field.decoration!.focusedBorder!.borderSide, BorderSide.none);
      expect(
          (field.decoration!.focusedBorder as OutlineInputBorder).borderRadius,
          BorderRadius.circular(ChatComposerTokens.radius));
      expect(tester.widget<ElevatedButton>(send).onPressed, isNull);
      await tester.enterText(input, 'Support message');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(send).onPressed, isNotNull);
      await tester.tap(send);
      await tester.tap(attach);
      expect(sends, 1);
      expect(attachments, 1);
      rebuild(() => enabled = false);
      await tester.pump();
      expect(tester.widget<TextField>(input).enabled, false);
      expect(tester.widget<ElevatedButton>(send).onPressed, isNull);
      expect(tester.widget<IconButton>(attach).onPressed, isNull);
      expect(controller.text, 'Support message');
      expect(tester.takeException(), isNull);
    });
  }
}
