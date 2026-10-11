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
                    if (count.value > 0)
                      ChatMediaPreparationIndicator(count: count.value),
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
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
