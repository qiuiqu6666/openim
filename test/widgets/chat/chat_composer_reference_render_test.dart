import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../fixtures/chat/composer_99chat_reference.dart';

// Compare rendered output with an independent transcription of the pinned
// production reference, rather than verifying this implementation's constants.
void main() {
  for (final dark in [false, true]) {
    testWidgets('matches production 99chat row pixel for pixel / $dark',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TextEditingController();
      final focus = FocusNode();
      final boundaryKey = GlobalKey();
      final theme = ThemeData(
        platform: TargetPlatform.iOS,
        brightness: dark ? Brightness.dark : Brightness.light,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: dark ? Colors.white : const Color(0xFF1E90FF),
          selectionColor: const Color(0xFF1E90FF).withValues(alpha: .22),
          selectionHandleColor: dark ? Colors.white : const Color(0xFF1E90FF),
        ),
      );

      await tester.runAsync(() async {
        for (final asset in ['voice', 'face', 'add']) {
          final picture = await vg.loadPicture(
            SvgAssetLoader('assets/chat/composer/$asset.svg',
                packageName: 'openim_common'),
            null,
          );
          picture.picture.dispose();
        }
      });

      Future<(Size, Uint8List)> render(bool reference) async {
        await tester.pumpWidget(GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme: theme,
          home: Material(
            child: Column(children: [
              const Spacer(),
              RepaintBoundary(
                key: boundaryKey,
                child: reference
                    ? Composer99ChatReference(
                        dark: dark, controller: controller, focusNode: focus)
                    : ChatInputBox(
                        controller: controller,
                        focusNode: focus,
                        onTapVoice: () {},
                        onSend: (_) {},
                        toolbox: const SizedBox(),
                        voiceRecordBar: const SizedBox(height: 36),
                      ),
              ),
            ]),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final size = boundary.size;
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        // Unmount to keep focus/draft ownership independent between renders.
        await tester.pumpWidget(const SizedBox());
        return (size, bytes!);
      }

      for (final width in [375.0, 320.0]) {
        tester.view.physicalSize = Size(width, 812);
        for (final bottom in [34.0, 0.0]) {
          tester.view.padding = FakeViewPadding(bottom: bottom);
          for (final text in [
            '',
            ' ',
            'Message 123',
            'First line\nSecond line\nThird line'
          ]) {
            controller.text = text;
            final expected = await render(true);
            final actual = await render(false);
            final scenario =
                'dark=$dark width=$width bottom=$bottom text=$text';
            expect(actual.$1, expected.$1, reason: scenario);
            expect(actual.$2.length, expected.$2.length, reason: scenario);
            var differentPixels = 0;
            for (var offset = 0; offset < actual.$2.length; offset += 4) {
              if (actual.$2[offset] != expected.$2[offset] ||
                  actual.$2[offset + 1] != expected.$2[offset + 1] ||
                  actual.$2[offset + 2] != expected.$2[offset + 2] ||
                  actual.$2[offset + 3] != expected.$2[offset + 3]) {
                differentPixels++;
              }
            }
            expect(differentPixels, 0, reason: scenario);
          }
        }
      }
      controller.dispose();
      focus.dispose();
    });
  }
}
