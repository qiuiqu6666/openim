import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim_common/openim_common.dart';

import 'device_verification_login_fixture.dart';
import 'device_verification_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDevicePreviewFonts);

  for (final entrance in [
    (input: '13800138000', key: 'phoneNumber', value: '13800138000'),
    (input: '@12345678', key: 'account', value: '12345678'),
    (input: 'user@example.com', key: 'email', value: 'user@example.com'),
  ]) {
    testWidgets('${entrance.key} challenge authenticates only after SMS proof',
        (tester) async {
      final f = DeviceLoginFixture();
      await f.initialize(tester);
      addTearDown(() => f.dispose(tester));
      await f.startChallenge(tester, account: entrance.input);
      await f.logic.login();
      expect(f.adapter.requests, hasLength(1));
      final first = Map<String, dynamic>.from(f.adapter.requests.single.data);
      expect(first[entrance.key], entrance.value);
      expect(first['password'], IMUtils.generateMD5('password'));
      expect(first['deviceID'], fixtureDeviceID);
      for (final key in ['phoneNumber', 'account', 'email']) {
        if (key != entrance.key) expect(first[key], isNull);
      }
      if (entrance.key == 'phoneNumber') {
        expect(devicePhoneField, findsNothing);
      } else {
        expect(devicePhoneField, findsOneWidget);
        await tester.enterText(devicePhoneField, '13800138000');
        await tester.pump();
      }
      await f.sendCode(tester);
      f.expectNoSession();
      expect(find.text('17s'), findsOneWidget);
      final sent = f.adapter.requests[1];
      expect(sent.uri.path, '/account/code/send');
      expect(sent.data['usedFor'], 3);
      expect(sent.data['phoneNumber'], '13800138000');
      expect(sent.data['areaCode'], '+86');
      expect(sent.data['deviceID'], first['deviceID']);
      expect(sent.data['platform'], first['platform']);
      expect(sent.data['captchaVerifyParam'], 'test-slider-proof');
      expect(sent.data['password'], isNull);
      final index = await f.submitCode(tester);
      await tester.tap(deviceConfirm);
      await tester.pump();
      expect(f.adapter.requests, hasLength(3));
      expect(
          f.adapter.requests[index].data, {...first, 'verifyCode': '123456'});
      expect(f.adapter.requests[index].uri.path, '/account/login');
      f.expectNoSession();
      await f.respond(tester, index, data: fixtureCertificate);
      await f.finishLogin(tester);
      expect(f.im.logins, [('verified-user', 'verified-im')]);
      expect(DataSp.userID, 'verified-user');
      expect(DataSp.chatToken, 'verified-chat');
      expect(DataSp.imToken, 'verified-im');
      expect(f.cache.resets, 1);
      expect(find.text('main ready'), findsOneWidget);
      expect(find.text('设备验证'), findsNothing);
      expect(f.logic.pwdCtrl.text, isEmpty);
      expect(f.logic.verificationCodeCtrl.text, isEmpty);
      expect(f.credentials.saves.single.password, isNull);
      expect(f.credentials.saves.single.remember, isFalse);
      expect(f.credentials.saves.single.account, entrance.value);
      expect(
          f.adapter.requests.every((r) => r.headers['token'] == null), isTrue);
      expect(f.adapter.requests.map((r) => r.headers['operationID']).toSet(),
          hasLength(3));
    });
  }

  for (final code in [20006, 20007, 20008, 20009, 20081]) {
    testWidgets('verification error $code keeps the challenge retryable',
        (tester) async {
      final f = DeviceLoginFixture();
      await f.initialize(tester);
      addTearDown(() => f.dispose(tester));
      await f.startChallenge(tester);
      final failed = await f.submitCode(tester);
      await f.respond(tester, failed, code: code);
      f.expectNoSession();
      expect(find.text('设备验证'), findsOneWidget);
      expect(deviceConfirmButton(tester).onPressed, isNotNull);
      expect(deviceSendButton(tester).onPressed, isNotNull);
      final retry = await f.submitCode(tester, code: '654321');
      expect(f.adapter.requests[retry].data['verifyCode'], '654321');
      expect(f.adapter.requests[retry].data['password'],
          f.adapter.requests.first.data['password']);
      await f.respond(tester, retry, data: fixtureCertificate);
      await f.finishLogin(tester);
      expect(f.im.logins, hasLength(1));
      expect(find.text('main ready'), findsOneWidget);
    });
  }

  for (final code in [20001, 20082]) {
    testWidgets('fatal verification error $code returns to password form',
        (tester) async {
      final f = DeviceLoginFixture();
      await f.initialize(tester);
      addTearDown(() => f.dispose(tester));
      await f.startChallenge(tester);
      final index = await f.submitCode(tester);
      await f.respond(tester, index, code: code);
      await f.finishLogin(tester);
      f.expectNoSession();
      expect(find.text('设备验证'), findsNothing);
      expect(find.text('password entry'), findsOneWidget);
      expect(f.logic.formError, isNotNull);
      if (code == 20082) {
        expect(f.logic.formError, contains('已登录的设备'));
        expect(f.logic.formError, contains('绑定手机号'));
        Get.locale = const Locale('en', 'US');
        expect(f.logic.formError, contains('signed-in device'));
        expect(f.logic.formError, contains('phone'));
        Get.locale = const Locale('zh', 'CN');
      }
      expect(f.logic.submitting.value, isFalse);
      expect(f.adapter.requests, hasLength(2));
    });
  }

  for (final code in [20001, 20002, 20082, 20083]) {
    testWidgets('initial login error $code cannot open the challenge or home',
        (tester) async {
      final f = DeviceLoginFixture();
      await f.initialize(tester);
      addTearDown(() => f.dispose(tester));
      f.logic.phoneCtrl.text = '@12345678';
      f.logic.pwdCtrl.text = 'password';
      await tester.runAsync(() async {
        f.pendingLogin = f.logic.login();
        await waitForAuth(() => f.adapter.requests.length == 1);
        f.adapter.reply(0, code: code);
        await f.pendingLogin;
      });
      await tester.pump();
      f.expectNoSession();
      expect(find.text('设备验证'), findsNothing);
      expect(f.logic.formError, isNotNull);
      expect(f.logic.submitting.value, isFalse);
    });
  }

  testWidgets('back cancellation ignores a late valid verification response',
      (tester) async {
    final f = DeviceLoginFixture();
    await f.initialize(tester);
    addTearDown(() => f.dispose(tester));
    await f.startChallenge(tester);
    final index = await f.submitCode(tester);
    await tester.tap(find.byKey(const ValueKey('auth-form-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await f.finishLogin(tester);
    await f.respond(tester, index, data: fixtureCertificate);
    f.expectNoSession();
    expect(find.text('password entry'), findsOneWidget);
    expect(f.logic.submitting.value, isFalse);
    expect(f.logic.formError, isNull);
  });

  testWidgets('changing account cancels its challenge and ignores late proof',
      (tester) async {
    final f = DeviceLoginFixture();
    await f.initialize(tester);
    addTearDown(() => f.dispose(tester));
    await f.startChallenge(tester);
    final index = await f.submitCode(tester);
    f.logic.selectLoginType(LoginType.account);
    f.logic.phoneCtrl.text = '@new-account';
    f.logic.pwdCtrl.text = 'new-password';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await f.respond(tester, index, data: fixtureCertificate);
    await f.finishLogin(tester);
    f.expectNoSession();
    expect(find.text('设备验证'), findsNothing);
    expect(f.logic.phoneCtrl.text, '@new-account');
    expect(f.logic.pwdCtrl.text, 'new-password');
  });

  testWidgets('closing login removes the challenge and ignores late proof',
      (tester) async {
    final f = DeviceLoginFixture();
    await f.initialize(tester);
    addTearDown(() => f.dispose(tester));
    await f.startChallenge(tester);
    final index = await f.submitCode(tester);
    f.closeLogin();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await f.respond(tester, index, data: fixtureCertificate);
    await f.finishLogin(tester);
    f.expectNoSession();
    expect(find.text('设备验证'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed success stays on verification without partial login',
      (tester) async {
    final f = DeviceLoginFixture();
    await f.initialize(tester);
    addTearDown(() => f.dispose(tester));
    await f.startChallenge(tester);
    final index = await f.submitCode(tester);
    await f
        .respond(tester, index, data: {...fixtureCertificate, 'chatToken': ''});
    f.expectNoSession();
    expect(find.text('设备验证'), findsOneWidget);
    expect(deviceConfirmButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('auth-form-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await f.finishLogin(tester);
  });

  testWidgets(
      'late verification cannot overwrite a newer authenticated session',
      (tester) async {
    final f = DeviceLoginFixture();
    await f.initialize(tester);
    addTearDown(() => f.dispose(tester));
    await f.startChallenge(tester);
    final index = await f.submitCode(tester);
    await tester.runAsync(() async {
      await DataSp.putLoginCertificate(LoginCertificate.fromJson({
        'userID': 'new-session-user',
        'chatToken': 'new-session-chat',
        'imToken': 'new-session-im',
      }));
    });
    await f.respond(tester, index, data: fixtureCertificate);
    expect(DataSp.userID, 'new-session-user');
    expect(DataSp.chatToken, 'new-session-chat');
    expect(DataSp.imToken, 'new-session-im');
    expect(f.im.logins, isEmpty);
    expect(f.cache.resets, 0);
    expect(f.credentials.saves, isEmpty);
    f.closeLogin();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await f.finishLogin(tester);
    expect(DataSp.userID, 'new-session-user');
    expect(find.text('main ready'), findsNothing);
  });

  testWidgets(
      'a covered verification route cannot authenticate or pop its cover',
      (tester) async {
    final f = DeviceLoginFixture();
    await f.initialize(tester);
    addTearDown(() => f.dispose(tester));
    await f.startChallenge(tester);
    final index = await f.submitCode(tester);
    final navigator = Navigator.of(tester.element(deviceCodeField));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover screen'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await f.respond(tester, index, data: fixtureCertificate);
    f.expectNoSession();
    expect(find.text('cover screen'), findsOneWidget);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('设备验证'), findsOneWidget);
    expect(deviceConfirmButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('auth-form-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await f.finishLogin(tester);
    f.expectNoSession();
    expect(find.text('password entry'), findsOneWidget);
  });
}
