import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/pages/edit_signature_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';

class _SignatureService extends StubSettingsService {
  final saved = <String>[];
  @override
  bool get isProfileBackendAvailable => true;
  @override
  Future<void> updateSignature(String value) async {
    saved.add(value);
  }
}

void main() {
  testWidgets('signature editor saves emoji and can clear a saved signature',
      (tester) async {
    final store = SettingsDraftStore();
    final service = _SignatureService();
    addTearDown(store.dispose);
    addTearDown(Get.reset);
    Widget host() => ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            translations: TranslationService(),
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: EditSignaturePage(store: store, service: service)));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好👨‍👩‍👧‍👦');
    await tester.pump();
    expect(find.text('3/100'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(service.saved, ['你好👨‍👩‍👧‍👦']);
    expect(store.profileSignature, '你好👨‍👩‍👧‍👦');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(service.saved.last, '');
    expect(store.profileSignature, '');
  });

  test(
      'confirmed SDK signature replaces prior value and accepts remote clearing',
      () {
    final store = SettingsDraftStore()..setProfileSignature('旧签名');
    addTearDown(store.dispose);
    store.syncProfileSignature('新签名');
    expect(store.profileSignature, '新签名');
    store.syncProfileSignature('');
    expect(store.profileSignature, '');
  });
}
