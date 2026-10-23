import 'package:openim/pages/register/set_password/set_password_logic.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/forget_password/forget_password_logic.dart';
import 'package:openim/pages/forget_password/reset_password/reset_password_logic.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/pages/register/register_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _App extends GetxController implements AppController {
  Future<void>? updateCheck;
  int updateChecks = 0;
  @override
  Future<void> autoCheckVersionUpgrade() {
    updateChecks++;
    return updateCheck ?? Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Login extends LoginLogic {
  int codeRequests = 0;

  @override
  void getPackageInfo() {}

  @override
  Future<bool> sendVerificationCode() async {
    codeRequests++;
    return true;
  }
}

class _Registration extends SetPasswordLogic {
  _Registration(Map<String, dynamic> arguments)
      : super(initialArguments: arguments);
  int submissions = 0;
  @override
  Future<void> register() async {
    submissions++;
  }
}

class _Register extends RegisterLogic {
  _Registration? submitted;
  @override
  SetPasswordLogic createRegistration(Map<String, dynamic> arguments) =>
      submitted = _Registration(Map.unmodifiable(arguments));
  int codeRequests = 0;
  Completer<bool> response = Completer<bool>();

  @override
  Future<void> verifyCredentials({
    required String areaCode,
    String? phoneNumber,
    String? email,
    required String verificationCode,
    String? invitationCode,
  }) {
    codeRequests++;
    return response.future.then((accepted) {
      if (!accepted) throw StateError('Verification failed');
    });
  }
}

class _InvitedRegister extends _Register {
  @override
  bool get needInvitationCodeRegister => true;
}

class _UnexpectedHTTP implements HttpClientAdapter {
  int requests = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    requests++;
    return Future.error(StateError('Invalid input reached the server'));
  }
}

class _Forget extends ForgetPasswordLogic {
  int codeRequests = 0;
  int checks = 0;
  int resets = 0;
  Completer<void> response = Completer<void>();
  Completer<void> resetResponse = Completer<void>();

  @override
  Future<bool> sendVerificationCode() async {
    codeRequests++;
    return true;
  }

  Future<void> checkVerificationCode() {
    checks++;
    return response.future;
  }

  @override
  Future<void> resetPassword() {
    resets++;
    return resetResponse.future;
  }
}

void _fillRecovery(_Forget forget) {
  forget.phoneCtrl.text = '13800138000';
  forget.verificationCodeCtrl.text = '123456';
  forget.pwdCtrl.text = 'password1';
  forget.pwdAgainCtrl.text = 'password1';
}

class _Reset extends ResetPasswordLogic {
  int requests = 0;
  Completer<void> response = Completer<void>();

  @override
  // The base initializer needs routed arguments; this fixture tests submission.
  // ignore: must_call_super
  void onInit() {
    // These tests exercise submission ownership, without a routed API request.
    areaCode = '+86';
    phoneNumber = '13800138000';
    verificationCode = '123456';
  }

  @override
  Future<void> resetPassword() {
    requests++;
    return response.future;
  }
}

Widget _app() => GetMaterialApp(
      initialRoute: '/',
      builder: EasyLoading.init(),
      getPages: [
        GetPage(name: '/', page: () => const Scaffold(body: Text('auth form'))),
        GetPage(
            name: AppRoutes.login,
            page: () => const Scaffold(body: Text('login form'))),
        GetPage(
            name: AppRoutes.verifyPhone,
            page: () => const Scaffold(body: Text('verify form'))),
        GetPage(
            name: AppRoutes.setPassword,
            page: () => const Scaffold(body: Text('profile form'))),
        GetPage(
            name: AppRoutes.forgetPassword,
            page: () => const Scaffold(body: Text('recovery form'))),
        GetPage(
            name: AppRoutes.resetPassword,
            page: () => const Scaffold(body: Text('reset form'))),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Login login;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await DataSp.init();
    Get.put<IMController>(_IM(), permanent: true);
    Get.put<AppController>(_App(), permanent: true);
    login = Get.put<LoginLogic>(_Login(), permanent: true) as _Login;
  });

  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
  });

  testWidgets('login submits while update check is still pending',
      (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    await tester.pumpWidget(_app());
    final adapter = _UnexpectedHTTP();
    http.dio.httpClientAdapter = adapter;
    final app = Get.find<AppController>() as _App;
    final gate = Completer<void>();
    app.updateCheck = gate.future;
    login.selectLoginType(LoginType.phone);
    login.isPasswordLogin.value = false;
    login.phoneCtrl.text = '13800138000';
    login.verificationCodeCtrl.text = '123456';
    var completed = false;
    await tester.runAsync(() async {
      await login.login().timeout(const Duration(seconds: 3));
      completed = true;
    });
    await tester.pumpAndSettle();
    expect(app.updateChecks, greaterThan(0));
    expect(completed, isTrue);
    expect(login.formError, isNotNull,
        reason: 'The login attempt must run, not await the unresolved update.');
    expect(gate.isCompleted, isFalse);
    gate.complete();
    expect(completed, isTrue);
  });

  testWidgets('login method switches recalculate the active credential',
      (tester) async {
    login.phoneCtrl.text = '13800138000';
    login.pwdCtrl.text = 'password1';
    expect(login.enabled.value, isTrue);

    login.togglePasswordType();
    expect(login.isPasswordLogin.value, isFalse);
    expect(login.pwdCtrl.text, 'password1');
    expect(login.enabled.value, isFalse);

    login.verificationCodeCtrl.text = '123456';
    expect(login.enabled.value, isTrue);
    login.togglePasswordType();
    expect(login.isPasswordLogin.value, isTrue);
    expect(login.verificationCodeCtrl.text, '123456');
    expect(login.enabled.value, isTrue);
  });

  testWidgets(
      'explicit identity is preserved for numeric IDs and email-shaped IDs',
      (tester) async {
    for (final type in LoginType.values) {
      login.selectLoginType(type);
      for (final input in ['13800138000', '12345', 'user@example.com', '']) {
        login.phoneCtrl.text = input;
        expect(login.loginType.value, type);
        expect(login.operateType, type);
      }
    }
    login.selectLoginType(LoginType.account);
    login.togglePasswordType();
    expect(login.isPasswordLogin.value, isTrue);
    expect(await login.getVerificationCode(), isFalse);
    login.selectLoginType(LoginType.phone);
    login.areaCode.value = '+852';
    login.phoneCtrl.text = '51234567';
    expect(login.phone, '51234567');
    expect(login.account, isNull);
    login.selectLoginType(LoginType.account);
    login.phoneCtrl.text = '51234567';
    expect(login.account, '51234567');
    expect(login.phone, isNull);
  });

  testWidgets('empty targets cannot request a login or recovery code',
      (tester) async {
    await tester.pumpWidget(_app());
    for (final type in [LoginType.phone, LoginType.email]) {
      login.selectLoginType(type);
      login.phoneCtrl.text = '   ';
      expect(await login.getVerificationCode(), isFalse);
    }
    login.selectLoginType(LoginType.account);
    login.phoneCtrl.text = 'account';
    expect(await login.getVerificationCode(), isFalse);
    expect(login.codeRequests, 0);

    login.operateType = LoginType.phone;
    final forget = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    forget.phoneCtrl.text = '   ';
    expect(await forget.getVerificationCode(), isFalse);
    login.operateType = LoginType.email;
    expect(await forget.getVerificationCode(), isFalse);
    expect(forget.codeRequests, 0);
  });

  testWidgets('login code accepts trimmed email and phone identities',
      (tester) async {
    await tester.pumpWidget(_app());
    login.selectLoginType(LoginType.email);
    login.phoneCtrl.text = '  user@example.com  ';
    expect(await login.getVerificationCode(), isTrue);
    login.selectLoginType(LoginType.phone);
    login.phoneCtrl.text = ' 13800138000 ';
    expect(await login.getVerificationCode(), isTrue);
    expect(login.codeRequests, 2);
  });

  testWidgets('recovery explicitly switches from email to phone',
      (tester) async {
    await tester.pumpWidget(_app());
    login.operateType = LoginType.email;
    final forget = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    expect(forget.emailMode.value, isTrue);
    forget.selectEmail(false);
    forget.phoneCtrl.text = ' 13800138000 ';
    expect(await forget.getVerificationCode(), isTrue);
    expect(forget.codeRequests, 1);
    expect(forget.phone, '13800138000');
    expect(forget.email, isNull);
  });

  testWidgets('blank credentials and malformed targets never start login',
      (tester) async {
    await tester.pumpWidget(_app());
    http.dio = Dio();
    final adapter = _UnexpectedHTTP();
    http.dio.httpClientAdapter = adapter;
    addTearDown(() => http.dio.close(force: true));
    for (final type in LoginType.values) {
      login.selectLoginType(type);
      login.isPasswordLogin.value = true;
      login.phoneCtrl.text = '   ';
      login.pwdCtrl.text = 'password1';
      await login.login();
      expect(login.submitting.value, isFalse);

      login.phoneCtrl.text = switch (type) {
        LoginType.phone => '13800138000',
        LoginType.email => 'user@example.com',
        LoginType.account => 'account',
      };
      login.pwdCtrl.text = '   ';
      await login.login();
      if (type != LoginType.account) {
        login.togglePasswordType();
        login.verificationCodeCtrl.text = '   ';
        await login.login();
      }
      expect(login.submitting.value, isFalse);
    }
    login.selectLoginType(LoginType.phone);
    login.isPasswordLogin.value = false;
    login.verificationCodeCtrl.text = '123456';
    for (final target in ['123', 'invalid-phone', 'user@example.com']) {
      login.phoneCtrl.text = target;
      await login.login();
    }
    login.isPasswordLogin.value = true;
    login.selectLoginType(LoginType.email);
    login.phoneCtrl.text = 'user@';
    login.pwdCtrl.text = 'password1';
    await login.login();
    login.selectLoginType(LoginType.account);
    login.pwdCtrl.text = 'password1';
    login.phoneCtrl.text = '@@';
    await login.login();
    login.selectLoginType(LoginType.phone);
    login.isPasswordLogin.value = false;
    login.phoneCtrl.text = '13800138000';
    for (final code in ['123', 'abcdef']) {
      login.verificationCodeCtrl.text = code;
      await login.login();
    }
    expect(adapter.requests, 0);
    expect(DataSp.getLoginAccount(), isNull);
  });

  testWidgets('registration requires an invite only for the configured flow',
      (tester) async {
    await tester.pumpWidget(_app());
    login.operateType = LoginType.email;
    final register =
        Get.put<RegisterLogic>(_InvitedRegister()) as _InvitedRegister;
    register.nicknameCtrl.text = 'Captured name';
    register.phoneCtrl.text = 'user@example.com';
    register.verificationCodeCtrl.text = '123456';
    register.pwdCtrl.text = 'password1';
    register.pwdAgainCtrl.text = 'password1';
    register.invitationCodeCtrl.text = '   ';
    await register.next();
    expect(register.codeRequests, 0);
    expect(register.submitting.value, isFalse);
    register.invitationCodeCtrl.text = 'invite-from-server';
    final pending = register.next();
    expect(register.codeRequests, 1);
    register.response.complete(false);
    await pending;
  });

  testWidgets('invalid recovery phone, code or passwords never verifies',
      (tester) async {
    await tester.pumpWidget(_app());
    final forget = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    _fillRecovery(forget);
    forget.phoneCtrl.text = '   ';
    await forget.nextStep();
    _fillRecovery(forget);
    forget.verificationCodeCtrl.text = '   ';
    await forget.nextStep();
    _fillRecovery(forget);
    forget.verificationCodeCtrl.text = '12345';
    await forget.nextStep();
    _fillRecovery(forget);
    forget.pwdCtrl.text = 'short1';
    forget.pwdAgainCtrl.text = 'short1';
    await forget.nextStep();
    _fillRecovery(forget);
    forget.pwdAgainCtrl.text = 'password2';
    await forget.nextStep();
    expect(forget.checks, 0);
    expect(forget.resets, 0);
    expect(forget.submitting.value, isFalse);
  });

  testWidgets('blank reset passwords or code never submit the change',
      (tester) async {
    await tester.pumpWidget(_app());
    final reset = Get.put<ResetPasswordLogic>(_Reset()) as _Reset;
    reset.pwdCtrl.text = '   ';
    reset.pwdAgainCtrl.text = 'password1';
    await reset.confirmTheChanges();
    reset.pwdCtrl.text = 'password1';
    reset.pwdAgainCtrl.text = '   ';
    await reset.confirmTheChanges();
    reset.pwdAgainCtrl.text = 'password1';
    reset.verificationCode = '   ';
    await reset.confirmTheChanges();
    reset.verificationCode = '123456';
    reset.phoneNumber = 'invalid-phone';
    await reset.confirmTheChanges();
    expect(reset.requests, 0);
    expect(reset.submitting.value, isFalse);
  });

  testWidgets('registration verifies once and passes an immutable credential',
      (tester) async {
    await tester.pumpWidget(_app());
    login.operateType = LoginType.email;
    final register = Get.put<RegisterLogic>(_Register()) as _Register;
    register.nicknameCtrl.text = 'Captured name';
    register.phoneCtrl.text = '  first@example.com  ';
    register.verificationCodeCtrl.text = '123456';
    register.pwdCtrl.text = 'password1';
    register.pwdAgainCtrl.text = 'password1';
    final pending = register.next();
    expect(register.submitting.value, isTrue);
    await register.next();
    expect(register.codeRequests, 1);
    register.nicknameCtrl.text = 'Captured name';
    register.phoneCtrl.text = 'second@example.com';
    register.verificationCodeCtrl.text = '654321';
    register.pwdCtrl.text = 'password2';
    register.response.complete(true);
    await pending;
    await tester.pumpAndSettle();

    expect(register.submitted!.submissions, 1);
    expect(register.submitted!.initialArguments!['email'], 'first@example.com');
    expect(register.submitted!.initialArguments!['verificationCode'], '123456');
    expect(register.submitted!.initialArguments!['password'], 'password1');
    expect(register.submitted!.initialArguments!['nickname'], 'Captured name');
    expect(find.text('profile form'), findsNothing);
    expect(register.submitting.value, isFalse);
  });

  testWidgets('registration ignores a late verification after leaving',
      (tester) async {
    await tester.pumpWidget(_app());
    login.operateType = LoginType.phone;
    final register = Get.put<RegisterLogic>(_Register()) as _Register;
    register.nicknameCtrl.text = 'Captured name';
    register.phoneCtrl.text = '13800138000';
    register.verificationCodeCtrl.text = '123456';
    register.pwdCtrl.text = 'password1';
    register.pwdAgainCtrl.text = 'password1';
    final pending = register.next();
    await Get.delete<RegisterLogic>(force: true);
    register.response.complete(true);
    await pending;
    await tester.pumpAndSettle();

    expect(find.text('auth form'), findsOneWidget);
    expect(register.codeRequests, 1);
  });

  testWidgets('failed registration verification can be submitted again',
      (tester) async {
    await tester.pumpWidget(_app());
    login.operateType = LoginType.phone;
    final register = Get.put<RegisterLogic>(_Register()) as _Register;
    register.nicknameCtrl.text = 'Captured name';
    register.phoneCtrl.text = '13800138000';
    register.verificationCodeCtrl.text = '123456';
    register.pwdCtrl.text = 'password1';
    register.pwdAgainCtrl.text = 'password1';
    final first = register.next();
    register.response.complete(false);
    await first;
    expect(register.submitting.value, isFalse);
    register.response = Completer<bool>();
    final second = register.next();
    register.response.complete(false);
    await second;
    expect(register.codeRequests, 2);
    expect(find.text('auth form'), findsOneWidget);
  });

  testWidgets(
      'recovery resets once without consuming a preview before returning to login',
      (tester) async {
    await tester.pumpWidget(_app());
    Get.toNamed(AppRoutes.login);
    await tester.pumpAndSettle();
    Get.toNamed(AppRoutes.forgetPassword);
    await tester.pumpAndSettle();
    final forget = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    _fillRecovery(forget);
    late Future<void> pending;
    await tester.runAsync(() async {
      pending = forget.nextStep();
    });
    expect(forget.submitting.value, isTrue);
    await forget.nextStep();
    expect(forget.checks, 0);
    expect(forget.resets, 1);
    expect(find.text('recovery form'), findsOneWidget);
    await tester.runAsync(() async {
      forget.resetResponse.complete();
      await pending;
    });
    await tester.pumpAndSettle();

    expect(find.text('login form'), findsOneWidget);
    expect(DataSp.getLoginCertificate(), isNull);
  });

  testWidgets('recovery ignores a late reset after leaving', (tester) async {
    await tester.pumpWidget(_app());
    login.operateType = LoginType.phone;
    final forget = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    _fillRecovery(forget);
    final pending = forget.nextStep();
    await Get.delete<ForgetPasswordLogic>(force: true);
    forget.resetResponse.complete();
    await pending;
    await tester.pumpAndSettle();

    expect(find.text('auth form'), findsOneWidget);
    expect(forget.checks, 0);
    expect(forget.resets, 1);
  });

  testWidgets('failed recovery keeps the form and releases submission',
      (tester) async {
    await tester.pumpWidget(_app());
    login.operateType = LoginType.phone;
    final forget = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    _fillRecovery(forget);
    final pending = forget.nextStep();
    forget.resetResponse.completeError(StateError('wrong code'));
    await pending;

    expect(forget.submitting.value, isFalse);
    expect(forget.verificationCodeCtrl.text, '123456');
    expect(forget.pwdCtrl.text, 'password1');
    expect(forget.pwdAgainCtrl.text, 'password1');
    expect(forget.resets, 1);
    expect(find.text('auth form'), findsOneWidget);
  });

  testWidgets('failed password reset keeps all four fields for another attempt',
      (tester) async {
    await tester.pumpWidget(_app());
    final forget = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    _fillRecovery(forget);
    final pending = forget.nextStep();
    await tester.pump();
    expect(forget.resets, 1);
    forget.resetResponse.completeError(StateError('offline'));
    await pending;
    expect(forget.submitting.value, isFalse);
    expect(forget.phoneCtrl.text, '13800138000');
    expect(forget.verificationCodeCtrl.text, '123456');
    expect(forget.pwdCtrl.text, 'password1');
    expect(forget.pwdAgainCtrl.text, 'password1');
    expect(find.text('auth form'), findsOneWidget);
  });

  testWidgets('reset submits once and cannot navigate after leaving',
      (tester) async {
    await tester.pumpWidget(_app());
    Get.toNamed(AppRoutes.login);
    await tester.pumpAndSettle();
    Get.toNamed(AppRoutes.resetPassword);
    await tester.pumpAndSettle();
    final reset = Get.put<ResetPasswordLogic>(_Reset()) as _Reset;
    reset.pwdCtrl.text = 'password1';
    reset.pwdAgainCtrl.text = 'password1';
    final pending = reset.confirmTheChanges();
    expect(reset.submitting.value, isTrue);
    await reset.confirmTheChanges();
    expect(reset.requests, 1);
    await Get.delete<ResetPasswordLogic>(force: true);
    reset.response.complete();
    await pending;
    await tester.pumpAndSettle();

    expect(find.text('reset form'), findsOneWidget);
  });

  testWidgets('reset errors keep both passwords available for retry',
      (tester) async {
    await tester.pumpWidget(_app());
    final reset = Get.put<ResetPasswordLogic>(_Reset()) as _Reset;
    reset.pwdCtrl.text = 'password1';
    reset.pwdAgainCtrl.text = 'password1';
    final pending = reset.confirmTheChanges();
    reset.response.completeError(StateError('offline'));
    await pending;

    expect(reset.submitting.value, isFalse);
    expect(reset.pwdCtrl.text, 'password1');
    expect(reset.pwdAgainCtrl.text, 'password1');
    expect(find.text('auth form'), findsOneWidget);
  });
}
