import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_emoji_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('common emoji can be inserted and the panel can be closed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = TextEditingController();
    String? sent;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: ChatInputBox(
            controller: controller,
            toolbox: const SizedBox(),
            voiceRecordBar: const SizedBox(),
            onSend: (value) => sent = value,
          ),
        ),
      ),
    ));

    await tester.tap(find.byTooltip('表情面板'));
    await tester.pumpAndSettle();
    final panelHeight = tester.getSize(find.byType(ChatEmojiPanel)).height;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(panelHeight, closeTo(math.min(280.h, screenHeight * .36), 1));
    expect(find.byTooltip('切换键盘'), findsOneWidget);
    await tester.tap(find.text('😂').first);
    expect(controller.text, '😂');
    await tester.tap(find.byTooltip('删除表情'));
    expect(controller.text, isEmpty);
    await tester.tap(find.text('😂').first);
    await tester.pump();
    await tester.tap(find.text('发送'));
    expect(sent, '😂');
    await tester.longPress(find.text('😂').first);
    await tester.tap(find.byTooltip('收藏表情'));
    await tester.pump();
    expect(find.text('😂'), findsWidgets);
    expect(find.text(StrRes.emoji), findsNothing);
    await tester.tap(find.byTooltip('切换键盘'));
    await tester.pump();
    expect(find.byTooltip('表情面板'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('personal sticker tab opens inside the emoji panel',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: const Scaffold(
          body: ChatInputBox(
            toolbox: SizedBox(),
            voiceRecordBar: SizedBox(),
            stickerPanel: Center(child: Text('已同步的表情')),
          ),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('表情面板'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏表情'));
    await tester.pump();
    expect(find.text('已同步的表情'), findsOneWidget);
  });

  testWidgets('input and sticker panel fit a narrow dark screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData.dark(),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: const Scaffold(
          body: ChatInputBox(
            toolbox: SizedBox(),
            voiceRecordBar: SizedBox(),
            stickerPanel: Center(child: Text('收藏内容')),
          ),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('表情面板'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏表情'));
    await tester.pump();
    expect(find.text('收藏内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
