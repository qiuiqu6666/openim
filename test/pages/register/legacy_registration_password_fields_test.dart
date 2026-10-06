import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/register/set_password/widgets/legacy_registration_password_fields.dart';
import 'package:openim/widgets/auth/auth_reference.dart';
import 'package:openim/widgets/auth/auth_form_rules.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  setUp(() {
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
  });
  tearDown(Get.reset);

  testWidgets('legacy fields show confirmation errors after losing focus',
      (tester) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    addTearDown(password.dispose);
    addTearDown(confirmation.dispose);
    var submits = 0;
    var confirmationTouched = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (_, update) => ListenableBuilder(
              listenable: Listenable.merge([password, confirmation]),
              builder: (_, __) => LegacyRegistrationPasswordFields(
                passwordController: password,
                confirmationController: confirmation,
                enabled: true,
                confirmationError: confirmationTouched
                    ? AuthFormRules.confirmPassword(
                        confirmation.text, password.text)
                    : null,
                onConfirmationFocusChanged: (focused) {
                  if (!focused) update(() => confirmationTouched = true);
                },
                onSubmitted: () => submits++,
              ),
            ),
          ),
        ),
      ),
    ));
    final fields = find.byType(EditableText);
    expect(fields, findsNWidgets(2));
    final value = 'longPasswordWithMoreThan20Chars1';
    await tester.enterText(fields.at(0), value);
    expect(password.text, value);
    expect(tester.widget<EditableText>(fields.at(0)).autofillHints,
        contains(AutofillHints.newPassword));
    await tester.enterText(fields.at(1), 'different1');
    await tester.pump();
    expect(find.text(StrRes.twicePwdNoSame), findsNothing);
    await tester.tap(fields.at(0));
    await tester.pump();
    expect(find.text(StrRes.twicePwdNoSame), findsOneWidget);
    await tester.enterText(fields.at(1), value);
    await tester.pump();
    expect(find.text(StrRes.twicePwdNoSame), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submits, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy password visibility is independent for each field',
      (tester) async {
    final password = TextEditingController(text: 'password1');
    final confirmation = TextEditingController(text: 'password1');
    addTearDown(password.dispose);
    addTearDown(confirmation.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LegacyRegistrationPasswordFields(
          passwordController: password,
          confirmationController: confirmation,
          enabled: true,
        ),
      ),
    ));
    final fields = find.byType(EditableText);
    expect(tester.widget<EditableText>(fields.at(0)).obscureText, isTrue);
    expect(tester.widget<EditableText>(fields.at(1)).obscureText, isTrue);
    final toggle = find
        .byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '显示密码')
        .first;
    expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byIcon(Icons.visibility_off_outlined).first);
    await tester.pump();
    expect(tester.widget<EditableText>(fields.at(0)).obscureText, isFalse);
    expect(tester.widget<EditableText>(fields.at(1)).obscureText, isTrue);
    expect(find.byType(AuthTextField), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
}
