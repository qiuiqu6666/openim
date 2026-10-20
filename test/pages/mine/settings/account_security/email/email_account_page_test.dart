import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/account_security/email/email_account_page.dart';
import 'package:openim/pages/mine/settings/account_security/email/email_account_service.dart';
import 'package:openim/pages/mine/settings/verification_code_result.dart';
import 'package:openim/pages/mine/settings/account_security/email/email_input_cell.dart';
import 'package:openim_common/openim_common.dart';

class _Service implements EmailAccountService {
  String email = '';
  bool active = true;
  Object? failure;
  Completer<void>? pending;
  int saves = 0;
  Map<String, Object>? saved;
  @override
  bool get isCurrent => active;
  @override
  Future<String> load() async => email;
  @override
  Future<VerificationCodeResult> send(
          String email, String purpose, String captcha) =>
      throw UnimplementedError();
  @override
  Future<void> save(
      {required bool changing,
      required String email,
      required String code,
      required String oldCode,
      required String password}) async {
    saves++;
    saved = {
      'changing': changing,
      'email': email,
      'code': code,
      'oldCode': oldCode,
      'password': password
    };
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }
}

Finder field(String label) => find.descendant(
      of: find
          .byWidgetPredicate((w) => w is EmailInputCell && w.label == label),
      matching: find.byType(EditableText),
    );
Finder code(String label) => find.descendant(
      of: find
          .byWidgetPredicate((w) => w is EmailInputCell && w.label == label),
      matching: find.byType(EditableText),
    );

Future<void> _mount(WidgetTester tester, _Service service,
    {bool dark = false, double scale = 1}) async {
  Get.locale = const Locale('en', 'US');
  await tester.pumpWidget(GetMaterialApp(
    locale: const Locale('en', 'US'),
    translations: TranslationService(),
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: EmailAccountPage(service: service)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);
  testWidgets(
      'binding requires password and destination code and retains failure',
      (tester) async {
    final service = _Service()..failure = StateError('offline');
    await _mount(tester, service);
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(service.saves, 0);
    await tester.enterText(field('Login password'), 'Example123');
    await tester.enterText(field('New email'), 'new@example.test');
    await tester.enterText(code('Email code'), '123456');
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
    expect(service.saved!['changing'], false);
    expect(find.text('new@example.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('change requires both codes and blocks duplicate submits',
      (tester) async {
    final service = _Service()
      ..email = 'old@example.test'
      ..pending = Completer<void>();
    await _mount(tester, service);
    expect(field('Login password'), findsNothing);
    await tester.enterText(field('New email'), 'next@example.test');
    await tester.enterText(code('Email code'), '123456');
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(service.saves, 0);
    await tester.enterText(code('Current email code'), '654321');
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(service.saves, 1);
    expect(service.saved!['oldCode'], '654321');
    await tester.pumpWidget(const SizedBox());
    service.pending!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('email form controls have accessible labels and touch targets',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester, _Service());
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets('email form supports large text ${dark ? "dark" : "light"}',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(tester, _Service()..email = 'long-address@example.test',
          dark: dark, scale: 2);
      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
