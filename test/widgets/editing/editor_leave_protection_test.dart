import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/pages/edit_signature_page.dart';
import 'package:openim/pages/mine/settings/pages/feedback_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final dark in [false, true]) {
    for (final feedback in [false, true]) {
      testWidgets('editor protects toolbar and system back: $feedback / $dark',
          (tester) async {
        final store = SettingsDraftStore();
        addTearDown(store.dispose);
        addTearDown(Get.reset);
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => GetMaterialApp(
                locale: const Locale('zh', 'CN'),
                translations: TranslationService(),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('zh', 'CN')],
                theme: ThemeData(
                    brightness: dark ? Brightness.dark : Brightness.light),
                home: Builder(
                    builder: (context) => Scaffold(
                        body: TextButton(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => feedback
                                        ? const FeedbackPage(
                                            service: StubSettingsService())
                                        : EditSignaturePage(
                                            store: store,
                                            service:
                                                const StubSettingsService()))),
                            child: const Text('Open editor')))))));
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '未提交的内容🙂');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).first);
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的内容？'), findsOneWidget);
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(find.text('未提交的内容🙂'), findsOneWidget);
        final context = tester.element(find.byType(TextField).first);
        await Navigator.of(context).maybePop();
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的内容？'), findsOneWidget);
        await tester.tap(find.text('放弃修改'));
        await tester.pumpAndSettle();
        expect(find.text('Open editor'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
