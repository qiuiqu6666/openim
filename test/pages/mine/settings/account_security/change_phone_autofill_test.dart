import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/change_phone_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';

class _Security extends StubSettingsService {
  final submissions = <(String, String, String, String?)>[];
  @override
  bool get isSecurityBackendAvailable => true;
  @override
  String get securityAreaCode => '+855';
  @override
  bool get securitySmsExempt => false;
  @override
  Future<void> refreshSecurity() async {}
  @override
  Future<void> changePhone({
    required String phone,
    required String oldCode,
    required String newCode,
    String? areaCode,
  }) async {
    submissions.add((phone, oldCode, newCode, areaCode));
    // Keep the page open to inspect state after a failed server request.
    throw StateError('synthetic server rejection');
  }
}

Finder _code(String key) => find.descendant(
    of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

Future<void> _platformFill(
    WidgetTester tester, Finder field, String code) async {
  await tester.showKeyboard(field);
  tester.testTextInput.updateEditingValue(TextEditingValue(
      text: code, selection: TextSelection.collapsed(offset: code.length)));
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() async => EasyLoading.dismiss(animation: false));
  for (final brightness in Brightness.values) {
    testWidgets('platform OTP preserves old/new codes: $brightness',
        (tester) async {
      final service = _Security();
      await tester.pumpWidget(MaterialApp(
        builder: EasyLoading.init(),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: brightness, platform: TargetPlatform.iOS),
        home: ChangePhonePage(
          service: service,
          isBound: true,
          currentPhone: '616003856',
        ),
      ));
      await tester.pumpAndSettle();
      final oldField = _code('change-phone-old-code');
      expect(tester.widget<TextField>(oldField).autofillHints,
          contains(AutofillHints.oneTimeCode));
      await _platformFill(tester, oldField, '012345');
      await tester.tap(find.widgetWithText(ElevatedButton, '下一步'));
      await tester.pumpAndSettle();
      final newField = _code('change-phone-new-code');
      expect(oldField, findsNothing);
      expect(tester.widget<TextField>(newField).controller!.text, isEmpty);
      expect(tester.widget<TextField>(newField).autofillHints,
          contains(AutofillHints.oneTimeCode));
      await tester.enterText(find.byType(TextField).first, '968539615');
      await _platformFill(tester, newField, '297147');
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, '完成'));
      await tester.tap(find.widgetWithText(ElevatedButton, '完成'));
      await tester.pumpAndSettle();
      expect(service.submissions, [('968539615', '012345', '297147', '+855')]);
      await EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '返回上一步'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(oldField).controller!.text, '012345');
      expect(tester.takeException(), isNull);
    });
  }
}
