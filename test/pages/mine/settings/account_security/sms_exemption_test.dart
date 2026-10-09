import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/change_password_page.dart';
import 'package:openim/pages/mine/settings/pages/change_phone_page.dart';
import 'package:openim/pages/mine/settings/pages/change_trade_password_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';

class _Security extends StubSettingsService {
  bool exempt = true;
  bool unavailable = false;
  int saves = 0;
  String? code;
  String? newCode;
  @override
  bool get isSecurityBackendAvailable => true;
  @override
  bool get securitySmsExempt => exempt;
  @override
  Future<void> refreshSecurity() async {
    if (unavailable) throw StateError('unavailable');
  }

  @override
  Future<void> changePasswordWithPhoneCode(
      {required String phone,
      required String code,
      required String newPassword}) async {
    saves++;
    this.code = code;
  }

  @override
  Future<void> resetTradePassword(
      {required String code, required String password}) async {
    saves++;
    this.code = code;
  }

  @override
  Future<void> changePhone(
      {required String phone,
      required String oldCode,
      required String newCode,
      String? areaCode}) async {
    saves++;
    code = oldCode;
    this.newCode = newCode;
  }

  @override
  Future<void> bindPhone(
      {required String phone, required String code, String? areaCode}) async {
    saves++;
    this.code = code;
  }
}

Widget _host(Widget page, Brightness brightness) => MaterialApp(
      builder: EasyLoading.init(),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      home: page,
    );

Future<void> _fillPasswords(WidgetTester tester, String password) async {
  expect(find.byType(TextField), findsNWidgets(2));
  await tester.enterText(find.byType(TextField).at(0), password);
  await tester.enterText(find.byType(TextField).at(1), password);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
  });
  test('missing or non-boolean profile flag never grants exemption', () {
    for (final value in [null, false, 1, 'true']) {
      expect(
          UserFullInfo.fromJson({'smsVerificationExempt': value})
              .smsVerificationExempt,
          false);
    }
    expect(
        UserFullInfo.fromJson({'smsVerificationExempt': true})
            .smsVerificationExempt,
        true);
  });

  for (final brightness in Brightness.values) {
    testWidgets('login password skips SMS with current exemption: $brightness',
        (tester) async {
      final service = _Security();
      await tester.pumpWidget(_host(
          ChangePasswordPage(service: service, phoneNumber: '13800138000'),
          brightness));
      await tester.pumpAndSettle();
      expect(find.text('验证码'), findsNothing);
      expect(find.text('旧密码'), findsNothing);
      await _fillPasswords(tester, 'Password123');
      await tester.tap(find.widgetWithText(ElevatedButton, '完成'));
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(service.code, '');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'payment password skips SMS with current exemption: $brightness',
        (tester) async {
      final service = _Security();
      await tester.pumpWidget(_host(
          ChangeTradePasswordPage(service: service, phoneNumber: '13800138000'),
          brightness));
      await tester.pumpAndSettle();
      expect(find.text('验证码'), findsNothing);
      expect(find.text('原密码'), findsNothing);
      await _fillPasswords(tester, '654321');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(service.code, '');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    for (final bound in [true, false]) {
      testWidgets('phone edit skips SMS, bound=$bound: $brightness',
          (tester) async {
        final service = _Security();
        await tester.pumpWidget(_host(
            ChangePhonePage(
                service: service,
                isBound: bound,
                currentPhone: bound ? '13800138000' : ''),
            brightness));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('获取验证码'), findsNothing);
        await tester.enterText(find.byType(TextField), '13900139000');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();
        expect(service.saves, 1);
        expect(service.code, '');
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        if (bound) expect(service.newCode, '');
      });
    }
  }

  testWidgets('revocation at submit restores SMS without sending a mutation',
      (tester) async {
    final service = _Security();
    await tester.pumpWidget(_host(
        ChangePasswordPage(service: service, phoneNumber: '13800138000'),
        Brightness.light));
    await tester.pumpAndSettle();
    await _fillPasswords(tester, 'Password123');
    service.exempt = false;
    await tester.tap(find.widgetWithText(ElevatedButton, '完成'));
    await tester.pumpAndSettle();
    expect(service.saves, 0);
    expect(find.text('验证码'), findsOneWidget);
  });

  testWidgets('policy load failure blocks submit and offers retry',
      (tester) async {
    final service = _Security()..unavailable = true;
    await tester.pumpWidget(_host(
        ChangeTradePasswordPage(service: service, phoneNumber: '13800138000'),
        Brightness.light));
    await tester.pumpAndSettle();
    expect(find.text('安全设置加载失败，点击重试'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    service.unavailable = false;
    await tester.tap(find.text('安全设置加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('验证码'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
