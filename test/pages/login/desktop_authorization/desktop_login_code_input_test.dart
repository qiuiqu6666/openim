import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/login/desktop_authorization/widgets/desktop_login_code_input.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

void main() {
  Future<void> showInput(WidgetTester tester, TextEditingController controller,
      {bool enabled = true,
      Brightness brightness = Brightness.light,
      double width = 342,
      double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        fontFamily: Platform.environment['DESKTOP_CODE_PREVIEW'] == null
            ? null
            : 'DesktopCodePreview',
      ),
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const Key('code-preview'),
              child: ColoredBox(
                color: ThemeData(brightness: brightness).colorScheme.surface,
                child: SizedBox(
                  width: width,
                  child: DesktopLoginCodeInput(
                    controller: controller,
                    enabled: enabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('six boxes accept digits, preserve zero, limit length and delete',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await showInput(tester, controller);
    final pin = tester.widget<PinCodeTextField>(find.byType(PinCodeTextField));
    expect(pin.length, 6);
    expect(pin.pinTheme.shape, PinCodeFieldShape.box);
    await tester.enterText(find.byType(TextField), '0a1234567');
    await tester.pump();
    expect(controller.text, '012345');
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '01234', selection: TextSelection.collapsed(offset: 5)));
    await tester.pump();
    expect(controller.text, '01234');
    await tester.pumpWidget(const SizedBox());
    controller.text = '654321';
    expect(controller.text, '654321');
  });

  testWidgets('full code can be pasted and disabled input preserves the code',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await showInput(tester, controller);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': '609872'};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.longPressAt(tester.getTopLeft(find.byType(PinCodeTextField)) +
        const Offset(24, 26));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(controller.text, '609872');
    await showInput(tester, controller, enabled: false);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(controller.text, '609872');
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    testWidgets('small screen large text and accessibility ${brightness.name}',
        (tester) async {
      final controller = TextEditingController(text: '012345');
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      await showInput(tester, controller,
          brightness: brightness, width: 272, scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('输入电脑上的六位数字'), findsWidgets);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      final output = Platform.environment['DESKTOP_CODE_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
          await (FontLoader('DesktopCodePreview')
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
        });
        await showInput(tester, controller, brightness: brightness);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('code-preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/code-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
}
