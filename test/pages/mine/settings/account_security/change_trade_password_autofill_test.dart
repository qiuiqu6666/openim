import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/change_trade_password_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';

class _Security extends StubSettingsService {
  final submissions = <(String, String)>[];

  @override
  bool get isSecurityBackendAvailable => true;
  @override
  bool get securitySmsExempt => false;
  @override
  Future<void> refreshSecurity() async {}
  @override
  Future<void> resetTradePassword(
      {required String code, required String password}) async {
    submissions.add((code, password));
    throw StateError('synthetic server rejection');
  }
}

void main() {
  tearDown(() async => EasyLoading.dismiss(animation: false));

  for (final brightness in Brightness.values) {
    testWidgets('payment SMS autofill remains visible and submits: $brightness',
        (tester) async {
      final service = _Security();
      await tester.pumpWidget(MaterialApp(
        builder: EasyLoading.init(),
        theme: ThemeData(brightness: brightness, platform: TargetPlatform.iOS),
        home:
            ChangeTradePasswordPage(service: service, phoneNumber: '968539615'),
      ));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      final code = fields.at(0);
      expect(tester.widget<TextField>(code).autofillHints,
          [AutofillHints.oneTimeCode]);
      expect(tester.widget<TextField>(code).obscureText, isFalse);
      expect(tester.widget<TextField>(fields.at(1)).autofillHints, isNull);
      await tester.showKeyboard(code);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
          text: '012345', selection: TextSelection.collapsed(offset: 6)));
      await tester.pumpAndSettle();
      expect(find.text('012345'), findsOneWidget);
      await tester.enterText(fields.at(1), '654321');
      await tester.enterText(fields.at(2), '654321');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(code).controller!.text, '012345');
      final done = find.byType(ElevatedButton);
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(service.submissions, [('012345', '654321')]);
      expect(find.text('012345'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('current payment password does not request SMS autofill',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeTradePasswordPage(service: _Security()),
    ));
    await tester.pumpAndSettle();
    final old = tester.widget<TextField>(find.byType(TextField).first);
    expect(old.autofillHints, isNull);
    expect(old.obscureText, isTrue);
  });
}
