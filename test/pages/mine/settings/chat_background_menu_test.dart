import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/appearance/chat_background/chat_background_menu.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('menu actions, large text and disabled state dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];
      Future<void> render(bool busy) => tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ChatBackgroundMenu(
              busy: busy,
              onSelect: () => calls.add('select'),
              onPhotos: () => calls.add('photos'),
              onCamera: () => calls.add('camera'),
            ),
          ));
      await render(false);
      final semantics = tester.ensureSemantics();
      await tester.tap(find.text('Choose Background'));
      await tester.tap(find.text('Choose from Photos'));
      await tester.tap(find.text('Take a Photo'));
      expect(calls, ['select', 'photos', 'camera']);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await render(true);
      await tester.tap(find.text('Take a Photo'));
      expect(calls.length, 3);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
