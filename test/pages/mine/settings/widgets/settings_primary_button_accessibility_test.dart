import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('long button label stays readable and still while busy: $dark',
        (tester) async {
      var busy = false;
      var calls = 0;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 812), textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: Center(
                child: SizedBox(
                    width: 320,
                    child: StatefulBuilder(builder: (_, setState) {
                      update = setState;
                      return SettingsPrimaryButton(
                          text: 'Save configuration',
                          loading: busy,
                          onPressed: () => calls++);
                    })),
              )))));
      final label = find.text('Save configuration');
      final before = tester.getRect(label);
      final beforeButton = tester.getRect(find.byType(ElevatedButton));
      await tester.tap(label);
      expect(calls, 1);
      update(() => busy = true);
      await tester.pump();
      expect(tester.getRect(label), before);
      expect(tester.getRect(find.byType(ElevatedButton)), beforeButton);
      expect(before.top, greaterThanOrEqualTo(beforeButton.top));
      expect(before.bottom, lessThanOrEqualTo(beforeButton.bottom));
      expect(before.left, greaterThanOrEqualTo(beforeButton.left));
      expect(before.right, lessThanOrEqualTo(beforeButton.right));
      await tester.tap(label);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
