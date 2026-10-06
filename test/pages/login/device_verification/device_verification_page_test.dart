import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/login/device_verification/device_verification.dart';
import 'package:openim/pages/mine/settings/verification_code_result.dart';
import 'package:openim/widgets/auth/auth_reference.dart';
import 'package:openim_common/openim_common.dart';

import 'device_verification_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDevicePreviewFonts);
  setUp(() => Get.testMode = true);
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });

  testWidgets('static preview never claims to send or verify a code',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    await mountDevicePage(tester, const DeviceVerificationPage());
    expect(find.text('设备验证'), findsOneWidget);
    expect(deviceSendButton(tester).onPressed, isNull);
    await tester.enterText(deviceCodeField, '123456');
    expect(deviceConfirmButton(tester).onPressed, isNull);
    expect(find.text('验证码已发送'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('known phone is reused while only its mask is displayed',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    final targets = <(String, String)>[];
    await mountDevicePage(
        tester,
        DeviceVerificationPage(
          phoneMasked: '138****8000',
          initialPhoneNumber: '13800138000',
          initialAreaCode: '+86',
          onSendCode: (phone, area) async {
            targets.add((phone, area));
            return const VerificationCodeResult(
                captchaVerified: true, sent: true, retryAfter: 17);
          },
        ));
    expect(devicePhoneField, findsNothing);
    expect(find.textContaining('138****8000'), findsOneWidget);
    expect(find.textContaining('13800138000'), findsNothing);
    await tester.tap(deviceSend);
    await tester.pump();
    expect(targets, [('13800138000', '+86')]);
    expect(find.text('17s'), findsOneWidget);
    expect(deviceSendButton(tester).onPressed, isNull);
    await clearDevicePage(tester);
  });

  testWidgets('unknown account must supply a valid bound phone before sending',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    final targets = <(String, String)>[];
    await mountDevicePage(
        tester,
        DeviceVerificationPage(
          requiresPhoneInput: true,
          onSendCode: (phone, area) async {
            targets.add((phone, area));
            return const VerificationCodeResult(
                captchaVerified: true, sent: true, retryAfter: 9);
          },
        ));
    expect(devicePhoneField, findsOneWidget);
    await tester.tap(deviceSend);
    await tester.pump();
    expect(targets, isEmpty);
    await tester.enterText(devicePhoneField, '123');
    await tester.tap(deviceSend);
    await tester.pump();
    expect(targets, isEmpty);
    await tester.enterText(devicePhoneField, '13800138000');
    await tester.pump();
    await tester.tap(deviceSend);
    await tester.pump();
    expect(targets, [('13800138000', '+86')]);
    expect(find.text('9s'), findsOneWidget);
    await tester.enterText(deviceCodeField, '123456');
    await tester.enterText(devicePhoneField, '13900139000');
    await tester.pump();
    expect(tester.widget<TextField>(deviceCodeField).controller!.text, isEmpty);
    expect(find.text('9s'), findsNothing);
    expect(deviceSendButton(tester).onPressed, isNotNull);
    await clearDevicePage(tester);
  });

  testWidgets('send is single-flight and cancelled slider has no cooldown',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    final pending = Completer<VerificationCodeResult?>();
    var calls = 0;
    await mountDevicePage(
        tester,
        DeviceVerificationPage(
          initialPhoneNumber: '13800138000',
          onSendCode: (_, __) {
            calls++;
            return pending.future;
          },
          onVerify: (_) async => false,
        ));
    await tester.enterText(deviceCodeField, '123456');
    await tester.tap(deviceSend);
    await tester.pump();
    await tester.tap(deviceSend);
    expect(calls, 1);
    expect(deviceSendButton(tester).onPressed, isNull);
    expect(deviceConfirmButton(tester).onPressed, isNull);
    expect(tester.widget<TextField>(deviceCodeField).enabled, isFalse);
    pending.complete(null);
    await tester.pump();
    expect(deviceSendButton(tester).onPressed, isNotNull);
    expect(deviceConfirmButton(tester).onPressed, isNotNull);
    expect(find.text('验证码已发送'), findsNothing);
    expect(find.text('60s'), findsNothing);
  });

  testWidgets('failed slider can retry; successful slider observes retryAfter',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    final responses = [
      const VerificationCodeResult(captchaVerified: false, sent: false),
      const VerificationCodeResult(
          captchaVerified: true, sent: false, retryAfter: 4),
    ];
    var calls = 0;
    await mountDevicePage(
        tester,
        DeviceVerificationPage(
          initialPhoneNumber: '13800138000',
          onSendCode: (_, __) async => responses[calls++],
        ));
    await tester.tap(deviceSend);
    await tester.pump();
    expect(deviceSendButton(tester).onPressed, isNotNull);
    expect(find.text('60s'), findsNothing);
    await tester.tap(deviceSend);
    await tester.pump();
    expect(calls, 2);
    expect(deviceSendButton(tester).onPressed, isNull);
    expect(find.text('4s'), findsOneWidget);
    expect(find.text('验证码已发送'), findsNothing);
  });

  testWidgets('six numeric digits are required and verify is single-flight',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    final pending = Completer<bool>();
    final codes = <String>[];
    await mountDevicePage(
        tester,
        DeviceVerificationPage(
          initialPhoneNumber: '13800138000',
          onSendCode: (_, __) async => null,
          onVerify: (code) {
            codes.add(code);
            return pending.future;
          },
        ));
    await tester.enterText(deviceCodeField, '12345');
    expect(deviceConfirmButton(tester).onPressed, isNull);
    await tester.enterText(deviceCodeField, '12a34567');
    await tester.pump();
    expect(
        tester.widget<TextField>(deviceCodeField).controller!.text, '123456');
    await tester.tap(deviceConfirm);
    await tester.pump();
    await tester.tap(deviceConfirm);
    expect(codes, ['123456']);
    expect(deviceConfirmButton(tester).loading, isTrue);
    expect(deviceSendButton(tester).onPressed, isNull);
    expect(tester.widget<TextField>(deviceCodeField).enabled, isFalse);
    pending.complete(false);
    await tester.pump();
    expect(deviceConfirmButton(tester).loading, isFalse);
    expect(deviceConfirmButton(tester).onPressed, isNotNull);
    expect(find.text('设备验证'), findsOneWidget);
  });

  for (final action in ['send', 'verify']) {
    testWidgets('late $action callback is ignored after the page is disposed',
        (tester) async {
      final send = Completer<VerificationCodeResult?>();
      final verify = Completer<bool>();
      await mountDevicePage(
          tester,
          DeviceVerificationPage(
            initialPhoneNumber: '13800138000',
            onSendCode: (_, __) => send.future,
            onVerify: (_) => verify.future,
          ));
      await tester.enterText(deviceCodeField, '123456');
      await tester.pump();
      await tester.tap(action == 'send' ? deviceSend : deviceConfirm);
      await tester.pump();
      await clearDevicePage(tester);
      if (action == 'send') {
        send.complete(
            const VerificationCodeResult(captchaVerified: true, sent: true));
      } else {
        verify.complete(true);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('验证码已发送'), findsNothing);
      await clearDevicePage(tester);
      await tester.pump(const Duration(milliseconds: 2500));
    });
  }

  testWidgets('server failure restores controls and preserves entered code',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    var calls = 0;
    await mountDevicePage(
        tester,
        DeviceVerificationPage(
          initialPhoneNumber: '13800138000',
          onSendCode: (_, __) async => null,
          onVerify: (_) async {
            calls++;
            throw (20006, '验证码不正确');
          },
        ));
    await tester.enterText(deviceCodeField, '123456');
    await tester.pump();
    await tester.tap(deviceConfirm);
    await tester.pump();
    expect(calls, 1);
    expect(deviceConfirmButton(tester).loading, isFalse);
    expect(deviceConfirmButton(tester).onPressed, isNotNull);
    expect(
        tester.widget<TextField>(deviceCodeField).controller!.text, '123456');
    expect(find.text('设备验证'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await clearDevicePage(tester);
  });

  testWidgets('resend uses the server interval and resumes after its deadline',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    var calls = 0;
    await mountDevicePage(
        tester,
        DeviceVerificationPage(
          initialPhoneNumber: '13800138000',
          onSendCode: (_, __) async {
            calls++;
            return const VerificationCodeResult(
                captchaVerified: true, sent: true, retryAfter: 3);
          },
        ));
    await tester.tap(deviceSend);
    await tester.pump();
    expect(find.text('3s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2s'), findsOneWidget);
    expect(deviceSendButton(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(deviceSendButton(tester).onPressed, isNotNull);
    await tester.tap(deviceSend);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('3s'), findsOneWidget);
    await clearDevicePage(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('reference authentication palette remains readable dark=$dark',
        (tester) async {
      addTearDown(() => clearDevicePage(tester));
      await mountDevicePage(tester, const DeviceVerificationPage(), dark: dark);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AuthReferenceTokens.surface);
      final context = tester.element(deviceCodeField);
      expect(Theme.of(context).brightness, Brightness.light);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('actual previews cover input, busy, errors and constrained sizes',
      (tester) async {
    addTearDown(() => clearDevicePage(tester));
    for (final dark in [false, true]) {
      for (final state in [
        'known-phone',
        'account-phone',
        'input',
        'sending',
        'verifying',
        'error',
      ]) {
        final send = Completer<VerificationCodeResult?>();
        final verify = Completer<bool>();
        final key = GlobalKey();
        await mountDevicePage(
            tester,
            DeviceVerificationPage(
              phoneMasked: '138****8000',
              initialPhoneNumber: state == 'account-phone' ? '' : '13800138000',
              requiresPhoneInput: state == 'account-phone',
              onSendCode: (_, __) => send.future,
              onVerify: (_) => state == 'error'
                  ? Future.error((20006, '验证码不正确'))
                  : verify.future,
            ),
            dark: dark,
            boundaryKey: key);
        if (state == 'account-phone') {
          await tester.enterText(devicePhoneField, '13800138000');
        }
        if (['input', 'verifying', 'error'].contains(state)) {
          await tester.enterText(deviceCodeField, '123456');
        }
        await tester.pump();
        if (state == 'sending') await tester.tap(deviceSend);
        if (['verifying', 'error'].contains(state)) {
          await tester.tap(deviceConfirm);
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (state == 'error') {
          await tester.pumpAndSettle();
          expect(
              find.text(
                  HttpUtil.errorMessage((20006, '验证码不正确'), path: Urls.login)),
              findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await exportDevicePreview(tester, key,
            'device-verification-$state-${dark ? 'app-dark' : 'light'}');
        await clearDevicePage(tester);
        if (!send.isCompleted) send.complete(null);
        if (!verify.isCompleted) verify.complete(false);
        await tester.pump();
      }
    }
    for (final viewport in [
      (name: 'small', size: const Size(320, 568), scale: 1.0, keyboard: 0.0),
      (
        name: 'landscape',
        size: const Size(812, 375),
        scale: 1.0,
        keyboard: 0.0
      ),
      (
        name: 'large-text',
        size: const Size(375, 812),
        scale: 2.0,
        keyboard: 0.0
      ),
      (
        name: 'keyboard',
        size: const Size(375, 812),
        scale: 1.0,
        keyboard: 320.0
      ),
    ]) {
      final key = GlobalKey();
      await mountDevicePage(
          tester,
          DeviceVerificationPage(
            requiresPhoneInput: true,
            onSendCode: (_, __) async => null,
            onVerify: (_) async => false,
          ),
          size: viewport.size,
          scale: viewport.scale,
          keyboard: viewport.keyboard,
          boundaryKey: key);
      await tester.enterText(devicePhoneField, '13800138000');
      await tester.enterText(deviceCodeField, '123456');
      await tester.ensureVisible(deviceConfirm);
      await tester.pump();
      final button = tester.getRect(deviceConfirm);
      expect(button.right, lessThanOrEqualTo(viewport.size.width));
      expect(button.left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
      await exportDevicePreview(
          tester, key, 'device-verification-${viewport.name}');
      await clearDevicePage(tester);
    }
  }, skip: devicePreviewDirectory.isEmpty);
}
