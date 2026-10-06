import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets(
      'original composer icons are present in the packaged asset bundle',
      (tester) async {
    await tester.runAsync(() async {
      for (final asset in ['voice', 'face', 'add', 'keyboard']) {
        final bytes = await rootBundle
            .load('packages/openim_common/assets/chat/composer/$asset.svg');
        expect(bytes.lengthInBytes, greaterThan(0));
      }
    });
  });

  for (final dark in [false, true]) {
    testWidgets(
        '99chat composer keeps geometry and drafts across input modes / $dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final controller = TextEditingController();
      final focus = FocusNode();
      String? sent;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: Column(children: [
            const Expanded(child: SizedBox()),
            ChatInputBox(
              controller: controller,
              focusNode: focus,
              onTapVoice: () {},
              onSend: (value) => sent = value,
              toolbox: const SizedBox(height: 180),
              voiceRecordBar: const SizedBox(height: 36, child: Text('按住说话')),
            ),
          ])),
        ),
      ));
      await tester.pumpAndSettle();
      final bar = find.byKey(const ValueKey('chat-composer-bar'));
      final fill = find.byKey(const ValueKey('chat-composer-input-fill'));
      final decoration = tester.widget<ChatTextField>(fill).decoration!;
      final surface = find
          .descendant(
              of: find.byType(ChatInputBox), matching: find.byType(ColoredBox))
          .first;
      expect(tester.widget<ColoredBox>(surface).color,
          dark ? const Color(0xFF101114) : const Color(0xFFFFFFFF));
      expect(decoration.fillColor,
          dark ? const Color(0xFF1B1D22) : const Color(0xFFF1F3F5));
      expect(decoration.filled, isTrue);
      final border = decoration.enabledBorder! as OutlineInputBorder;
      expect(border.borderSide, BorderSide.none);
      expect(border.borderRadius, BorderRadius.circular(8));
      final iconRects = find
          .byType(SvgPicture)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      expect(tester.getRect(fill).left, iconRects[0].right + 10);
      expect(tester.getRect(fill).right, iconRects[1].left - 10);
      expect(tester.getSize(bar).height, closeTo(46.8, 1));
      expect(tester.getRect(find.byType(ChatInputBox)).bottom, 812);
      final icons = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
      expect(icons.length, 3);
      for (final icon in icons) {
        expect(icon.width, 26);
        expect(icon.height, 26);
      }

      // The parent retains draft ownership when the visual send button changes.
      controller.value = const TextEditingValue(
          text: '草稿消息', selection: TextSelection.collapsed(offset: 2));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
      expect(sent, '草稿消息');
      expect(controller.selection.baseOffset, 2);
      // The IME send action must keep focus and delegate to the parent, just
      // like the inline send button; the parent remains the draft owner.
      await tester.tap(fill);
      await tester.pump();
      sent = null;
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sent, '草稿消息');
      expect(focus.hasFocus, isTrue);
      expect(controller.text, '草稿消息');
      final selectionTheme = TextSelectionTheme.of(tester.element(fill));
      expect(selectionTheme.cursorColor,
          dark ? Colors.white : const Color(0xFF1E90FF));
      expect(selectionTheme.selectionColor,
          const Color(0xFF1E90FF).withValues(alpha: .22));
      expect(controller.text, '草稿消息');
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.tap(find.byTooltip(StrRes.voiceCapture));
      await tester.pump();
      expect(find.text('按住说话'), findsOneWidget);
      expect(controller.text, '草稿消息');
      await tester.tap(find.byTooltip(StrRes.voiceCapture));
      await tester.pump();
      expect(find.byType(ChatTextField), findsOneWidget);
      expect(controller.selection.baseOffset, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focus.dispose();
    });
  }

  testWidgets(
      'narrow composer grows for multiline and large text without losing actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: '第一行\n第二行\n第三行\n第四行');
    var sent = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: Column(children: [
          const Expanded(child: SizedBox()),
          ChatInputBox(
              controller: controller,
              onTapVoice: () {},
              onSend: (_) => sent++,
              toolbox: const SizedBox(),
              voiceRecordBar: const SizedBox(height: 36)),
        ])),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const ValueKey('chat-composer-bar'))).height,
        greaterThan(100));
    await tester.tap(find.widgetWithText(ElevatedButton, '发送'));
    expect(sent, 1);
    expect(controller.text, contains('第四行'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
