import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker_panel.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_emoji_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _draft = TextEditingValue(
  text: '保留原草稿内容',
  selection: TextSelection(baseOffset: 1, extentOffset: 4),
);
const _previewOutput =
    String.fromEnvironment('CHAT_BUILTIN_STICKER_PREVIEW_DIR');

class _Availability {
  const _Availability(
      {this.enabled = true, this.exited = false, this.builtin = true});
  final bool enabled, exited, builtin;
}

class _Fixture {
  final controller = TextEditingController.fromValue(_draft);
  final availability = ValueNotifier(const _Availability());
  final close = StreamController<void>.broadcast();
  final sent = <ChatBuiltinSticker>[];
  final boundary = GlobalKey();

  Future<void> mount(WidgetTester tester, Brightness brightness,
      {String? fontFamily}) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
      availability.dispose();
      close.close();
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(brightness: brightness, fontFamily: fontFamily),
        builder: (_, child) => RepaintBoundary(key: boundary, child: child!),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<_Availability>(
              valueListenable: availability,
              builder: (_, state, __) => ChatInputBox(
                controller: controller,
                style: fontFamily == null
                    ? null
                    : TextStyle(
                        fontFamily: fontFamily,
                        fontSize: ChatComposerTokens.fontSize,
                        height: ChatComposerTokens.lineHeight,
                        color: AppTokens.textPrimary(
                            dark: brightness == Brightness.dark)),
                enabled: state.enabled,
                isNotInGroup: state.exited,
                forceCloseToolboxSub: close.stream,
                toolbox: const SizedBox(),
                voiceRecordBar: const SizedBox(),
                stickerPanel: const Center(child: Text('个人表情面板')),
                builtinStickerPanel: state.builtin
                    ? ChatBuiltinStickerPanel(
                        onSend: (sticker) async => sent.add(sticker))
                    : null,
                builtinStickerIcon:
                    Image.asset(ChatBuiltinStickerCatalog.menuAssetPath),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('sdkEmojiPanel'.tr));
    await tester.pumpAndSettle();
  }

  Future<void> openBuiltin(WidgetTester tester) async {
    await tester.tap(find.byTooltip('99CHAT表情'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatBuiltinStickerPanel), findsOneWidget);
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets(
        'builtin pack sends directly and all existing tabs preserve the draft / $brightness',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, brightness);
      expect(find.byTooltip('sdkGestureEmoji'.tr), findsOneWidget);
      expect(find.byTooltip('sdkFavoriteEmoji'.tr), findsOneWidget);
      expect(find.byTooltip('sdkEmojiBackspace'.tr), findsOneWidget);
      await fixture.openBuiltin(tester);
      final icon = find.descendant(
          of: find.byTooltip('99CHAT表情'), matching: find.byType(Image));
      expect((tester.widget<Image>(icon).image as AssetImage).assetName,
          ChatBuiltinStickerCatalog.menuAssetPath);
      expect(find.byTooltip('sdkEmojiBackspace'.tr), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      final sticker = ChatBuiltinStickerCatalog.stickers.first;
      await tester.tap(find.byKey(ValueKey('builtin-sticker-${sticker.id}')));
      await tester.pumpAndSettle();
      expect(fixture.sent, [sticker]);
      expect(fixture.controller.value, _draft);
      await tester.tap(find.byTooltip('sdkFavoriteEmoji'.tr));
      await tester.pumpAndSettle();
      expect(find.text('个人表情面板'), findsOneWidget);
      expect(find.byType(ChatBuiltinStickerPanel), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(find.byTooltip('sdkGestureEmoji'.tr));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byTooltip('sdkEmojiPanel'.tr).last);
      await tester.pumpAndSettle();
      final send = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(send.style!.backgroundColor!.resolve({}), AppTokens.accent);
      expect(send.style!.foregroundColor!.resolve({}), AppTokens.onAccent);
      expect(fixture.controller.value, _draft);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'mute, leave and forced close hide builtin without losing draft / $brightness',
        (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, brightness);
      for (final mode in ['mute', 'leave', 'forced']) {
        if (find.byType(ChatEmojiPanel).evaluate().isEmpty) {
          await tester.tap(find.byTooltip('sdkEmojiPanel'.tr));
          await tester.pumpAndSettle();
        }
        await fixture.openBuiltin(tester);
        switch (mode) {
          case 'mute':
            fixture.availability.value = const _Availability(enabled: false);
          case 'leave':
            fixture.availability.value = const _Availability(exited: true);
          case 'forced':
            fixture.close.add(null);
        }
        await tester.pumpAndSettle();
        expect(find.byType(ChatEmojiPanel), findsNothing);
        expect(find.byType(ChatBuiltinStickerPanel), findsNothing);
        expect(fixture.controller.value, _draft);
        expect(fixture.sent, isEmpty);
        fixture.availability.value = const _Availability();
        await tester.pumpAndSettle();
        expect(find.byType(ChatEmojiPanel), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('export builtin composer ${brightness.name}',
        skip: _previewOutput.isEmpty, (tester) async {
      await tester.runAsync(() async {
        for (final family in [
          'ChatBuiltinPreview',
          'Microsoft YaHei UI',
          'Microsoft YaHei',
        ]) {
          await (FontLoader(family)
                ..addFont(File('C:/Windows/Fonts/msyh.ttc')
                    .readAsBytes()
                    .then(ByteData.sublistView)))
              .load();
        }
        await (FontLoader('MaterialIcons')
              ..addFont(File(
                      'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
                  .readAsBytes()
                  .then(ByteData.sublistView)))
            .load();
      });
      final fixture = _Fixture();
      await fixture.mount(tester, brightness, fontFamily: 'ChatBuiltinPreview');
      await fixture.openBuiltin(tester);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      await tester.runAsync(() async {
        for (final image in images) {
          await precacheImage(image.image, fixture.boundary.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      final render = fixture.boundary.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        await Directory(_previewOutput).create(recursive: true);
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_previewOutput/builtin-stickers-${brightness.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }

  testWidgets(
      'removing optional builtin injection restores the normal emoji tab',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester, Brightness.light);
    await fixture.openBuiltin(tester);
    fixture.availability.value = const _Availability(builtin: false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('99CHAT表情'), findsNothing);
    expect(find.byType(ChatBuiltinStickerPanel), findsNothing);
    expect(find.byTooltip('sdkEmojiBackspace'.tr), findsOneWidget);
    expect(fixture.controller.value, _draft);
    expect(tester.takeException(), isNull);
  });
}
