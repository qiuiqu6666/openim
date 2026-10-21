import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/media/widgets/chat_media_preparation_indicator.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final dark in [false, true]) {
    for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
      testWidgets(
          'preparation feedback is readable at large text: $dark $locale',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(Get.reset);
        final count = 2.obs;
        final failed = 0.obs;
        var retries = 0;
        await tester.pumpWidget(GetMaterialApp(
          locale: locale,
          translations: TranslationService(),
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Obx(() => Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (count.value > 0 || failed.value > 0)
                      ChatMediaPreparationIndicator(
                          count: count.value,
                          failedCount: failed.value,
                          onRetry: () {
                            retries++;
                            failed.value = 0;
                          }),
                    const TextField(),
                  ],
                )),
          ),
        ));
        expect(tester.takeException(), isNull);
        final text = locale.languageCode == 'zh'
            ? '正在准备附件（剩余 2 个）…'
            : 'Preparing attachments (2 remaining)…';
        expect(find.text(text), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Feedback does not intercept input while preparation continues.
        await tester.enterText(find.byType(TextField), 'next message');
        expect(find.text('next message'), findsOneWidget);
        count.value = 0;
        await tester.pump();
        expect(
            find.byKey(const ValueKey('chat-media-preparing')), findsNothing);
        expect(tester.takeException(), isNull);
        failed.value = 1;
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(TextButton), findsOneWidget);
        expect(tester.getSize(find.byType(TextButton)).height,
            greaterThanOrEqualTo(AppTokens.minimumTapSize));
        await tester.tap(find.byType(TextButton));
        await tester.pump();
        expect(retries, 1);
        expect(
            find.byKey(const ValueKey('chat-media-preparing')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets('video phases and recovery actions fit large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(Get.reset);
    var cancelled = 0, originals = 0;
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('en', 'US'),
      translations: TranslationService(),
      theme: ThemeData.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: Scaffold(
          body: ChatMediaPreparationIndicator(
              count: 2,
              failedCount: 1,
              stageLabel: 'Downloading videos (1) · Waiting to compress (1)',
              onCancel: () => cancelled++,
              onRetry: () {},
              onRetryOriginal: () => originals++)),
    ));
    expect(tester.takeException(), isNull);
    for (final text in [
      'Cancel pending preparation',
      'Retry failed videos as originals'
    ]) {
      final button = find.widgetWithText(TextButton, text);
      expect(tester.getSize(button).height,
          greaterThanOrEqualTo(AppTokens.minimumTapSize));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
    }
    expect(cancelled, 1);
    expect(originals, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
