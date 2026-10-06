import 'dart:async';
import 'dart:convert';
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
import 'package:openim/pages/forget_password/form/recovery_form_feedback.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/services/auth_credentials/auth_credentials_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Login extends LoginLogic {
  _Login(AuthCredentialsStore store) : super(credentialsStore: store);

  @override
  void getPackageInfo() {}
}

Future<T> _phase<T>(Future<T> future, String phase) => future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw TimeoutException('Recovery test stalled at $phase'));

class _RecoveryApi implements HttpClientAdapter {
  final verification = Completer<ResponseBody>();
  final reset = Completer<ResponseBody>();
  final verificationStarted = Completer<void>();
  final resetStarted = Completer<void>();
  final requests = <RequestOptions>[];
  bool failConnection = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancelFuture) {
    requests.add(options);
    if (failConnection) {
      return Future.error(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'Internal offline transport detail',
      ));
    }
    if (options.path.endsWith('/account/code/verify')) {
      if (!verificationStarted.isCompleted) verificationStarted.complete();
      return verification.future;
    }
    if (!resetStarted.isCompleted) resetStarted.complete();
    return reset.future;
  }

  @override
  void close({bool force = false}) {}

  ResponseBody response({int code = 0}) => ResponseBody.fromString(
          jsonEncode({'errCode': code, 'errMsg': 'Server detail'}), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
}

Future<ForgetPasswordLogic> _mount(WidgetTester tester) async {
  await tester.runAsync(() async {
    Get.put<IMController>(_IM(), permanent: true);
    Get.put<AppController>(_App(), permanent: true);
    final store = AuthCredentialsStore();
    Get.put<LoginLogic>(_Login(store), permanent: true);
    // Join the initial credential read in the same real asynchronous zone.
    await _phase(store.load(), 'login credential initialization');
  });
  await tester.pumpWidget(GetMaterialApp(
    initialRoute: AppRoutes.login,
    locale: const Locale('zh', 'CN'),
    translations: TranslationService(),
    builder: EasyLoading.init(),
    getPages: [
      GetPage(
          name: AppRoutes.login,
          page: () => const Scaffold(body: Text('login'))),
      GetPage(
          name: AppRoutes.forgetPassword,
          page: () => const Scaffold(body: Text('recovery'))),
    ],
  ));
  await tester.pumpAndSettle();
  Get.toNamed(AppRoutes.forgetPassword);
  await tester.pumpAndSettle();
  return Get.put<ForgetPasswordLogic>(ForgetPasswordLogic(), permanent: true);
}

void _validFields(ForgetPasswordLogic logic) {
  logic.phoneCtrl.text = '13800138000';
  logic.verificationCodeCtrl.text = '123456';
  logic.pwdCtrl.text = 'password1';
  logic.pwdAgainCtrl.text = 'password1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio originalDio;
  late _RecoveryApi api;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthCredentialsStore.instance.setRememberPassword(true);
    await DataSp.init();
    originalDio = http.dio;
    api = _RecoveryApi();
    http.dio = Dio()..httpClientAdapter = api;
  });

  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    http.dio.close(force: true);
    http.dio = originalDio;
    Get.reset();
  });

  testWidgets('incomplete recovery fields never reach verification or reset',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    logic.phoneCtrl.text = 'invalid';
    await logic.nextStep();
    _validFields(logic);
    logic.verificationCodeCtrl.text = '12345';
    await logic.nextStep();
    _validFields(logic);
    logic.pwdCtrl.text = '12345678';
    logic.pwdAgainCtrl.text = '12345678';
    await logic.nextStep();
    _validFields(logic);
    logic.pwdAgainCtrl.text = 'password2';
    await logic.nextStep();
    expect(api.requests, isEmpty);
    expect(logic.submitting.value, isFalse);
    expect(Get.currentRoute, AppRoutes.forgetPassword);
  });

  testWidgets('verification failure keeps all fields and skips password reset',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    late Future<void> pending;
    await tester.runAsync(() async {
      pending = logic.nextStep();
      await _phase(api.verificationStarted.future, 'verification request');
      api.verification.complete(api.response(code: 20006));
      await _phase(pending, 'request completion');
    });
    expect(api.requests, hasLength(1));
    expect(logic.phoneCtrl.text, '13800138000');
    expect(logic.verificationCodeCtrl.text, '123456');
    expect(logic.pwdCtrl.text, 'password1');
    expect(logic.pwdAgainCtrl.text, 'password1');
    expect(logic.submitting.value, isFalse);
    expect(Get.currentRoute, AppRoutes.forgetPassword);
    expect(logic.formError, '20006'.tr);
    for (final field in RecoveryField.values) {
      expect(logic.fieldError(field), isNull);
    }
    expect(EasyLoading.isShow, isFalse);
    Get.locale = const Locale('en', 'US');
    expect(logic.formError, '20006'.tr);
    expect(logic.formError, isNot(contains('Server detail')));
    logic.phoneCtrl.selection = const TextSelection.collapsed(offset: 4);
    expect(logic.formError, isNotNull);
    logic.phoneCtrl.text = '13900139000';
    expect(logic.formError, isNull);
  });

  testWidgets('one submission verifies and resets the same captured target',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    late Future<void> pending;
    await tester.runAsync(() async {
      pending = logic.nextStep();
      await _phase(api.verificationStarted.future, 'verification request');
    });
    await logic.nextStep();
    expect(api.requests, hasLength(1));
    expect(api.requests.single.data, containsPair('usedFor', 2));
    logic.phoneCtrl.text = '13900139000';
    logic.areaCode.value = '+1';
    logic.verificationCodeCtrl.text = '654321';
    logic.pwdCtrl.text = 'password2';
    logic.pwdAgainCtrl.text = 'password2';
    await tester.runAsync(() async {
      api.verification.complete(api.response());
      await _phase(api.resetStarted.future, 'reset request');
    });
    expect(api.requests, hasLength(2));
    final reset = api.requests.last;
    expect(reset.path, endsWith('/account/password/reset'));
    expect(reset.data, containsPair('phoneNumber', '13800138000'));
    expect(reset.data, containsPair('areaCode', '+86'));
    expect(reset.data, containsPair('verifyCode', '123456'));
    expect(
        reset.data, containsPair('password', IMUtils.generateMD5('password1')));
    await tester.runAsync(() async {
      api.reset.complete(api.response());
      await _phase(pending, 'request completion');
    });
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.login);
    expect(DataSp.getLoginCertificate(), isNull);
  });

  testWidgets('leaving during verification prevents the following reset',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _phase(api.verificationStarted.future, 'verification request');
      await Get.delete<ForgetPasswordLogic>(force: true);
      expect(logic.isClosed, isTrue);
      api.verification.complete(api.response());
      await _phase(pending, 'late verification completion');
    });
    expect(api.requests, hasLength(1));
    expect(Get.currentRoute, AppRoutes.forgetPassword);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late reset response cannot navigate after leaving',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _phase(api.verificationStarted.future, 'verification request');
      api.verification.complete(api.response());
      await _phase(api.resetStarted.future, 'reset request');
      expect(api.requests, hasLength(2));
      await Get.delete<ForgetPasswordLogic>(force: true);
      expect(logic.isClosed, isTrue);
      api.reset.complete(api.response());
      await _phase(pending, 'late reset completion');
    });
    expect(Get.currentRoute, AppRoutes.forgetPassword);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful reset updates the matching remembered password',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    final login = logic.loginController;
    login.phoneCtrl.text = '13800138000';
    login.areaCode.value = '+86';
    login.pwdCtrl.text = 'previous1';
    login.rememberPassword.value = true;
    await tester.runAsync(() async {
      await AuthCredentialsStore.instance.saveSuccessful(
        account: '13800138000',
        areaCode: '+86',
        loginType: 0,
        password: 'previous1',
        rememberPassword: true,
        isCurrent: () => true,
      );
      final pending = logic.nextStep();
      await _phase(api.verificationStarted.future, 'verification request');
      api.verification.complete(api.response());
      await _phase(api.resetStarted.future, 'reset request');
      api.reset.complete(api.response());
      await _phase(pending, 'request completion');
      final stored = await AuthCredentialsStore.instance.load();
      expect(stored.account, '13800138000');
      expect(stored.password, 'password1');
    });
    expect(login.pwdCtrl.text, 'password1');
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.login);
  });

  testWidgets('reset leaves another account and its remembered password intact',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    final login = logic.loginController;
    login.phoneCtrl.text = '13900139000';
    login.areaCode.value = '+86';
    login.pwdCtrl.text = 'previous1';
    login.rememberPassword.value = true;
    await tester.runAsync(() async {
      await AuthCredentialsStore.instance.saveSuccessful(
        account: '13900139000',
        areaCode: '+86',
        loginType: 0,
        password: 'previous1',
        rememberPassword: true,
        isCurrent: () => true,
      );
      final pending = logic.nextStep();
      await _phase(api.verificationStarted.future, 'verification request');
      api.verification.complete(api.response());
      await _phase(api.resetStarted.future, 'reset request');
      api.reset.complete(api.response());
      await _phase(pending, 'request completion');
      final stored = await AuthCredentialsStore.instance.load();
      expect(stored.account, '13900139000');
      expect(stored.password, 'previous1');
    });
    expect(login.pwdCtrl.text, 'previous1');
  });

  testWidgets('local errors wait for blur then update as the input changes',
      (tester) async {
    final logic = await _mount(tester);
    for (final field in RecoveryField.values) {
      expect(logic.fieldError(field), isNull);
    }
    logic.phoneCtrl.text = '123';
    expect(logic.fieldError(RecoveryField.phone), isNull);
    logic.onFocusChanged(RecoveryField.phone, false);
    expect(logic.fieldError(RecoveryField.phone), isNull);
    logic.onFocusChanged(RecoveryField.phone, true);
    logic.onFocusChanged(RecoveryField.phone, false);
    expect(logic.fieldError(RecoveryField.phone), StrRes.plsEnterRightPhone);
    logic.phoneCtrl.text = '13800138000';
    expect(logic.fieldError(RecoveryField.phone), isNull);

    logic.pwdCtrl.text = 'short1';
    expect(logic.fieldError(RecoveryField.password), isNull);
    logic.onFocusChanged(RecoveryField.password, true);
    logic.onFocusChanged(RecoveryField.password, false);
    expect(logic.fieldError(RecoveryField.password), isNotNull);
    logic.pwdCtrl.text = 'password1';
    expect(logic.fieldError(RecoveryField.password), isNull);
    logic.pwdAgainCtrl.text = 'password2';
    expect(logic.fieldError(RecoveryField.confirmation), isNull);
    logic.onFocusChanged(RecoveryField.confirmation, true);
    logic.onFocusChanged(RecoveryField.confirmation, false);
    expect(logic.fieldError(RecoveryField.confirmation), StrRes.twicePwdNoSame);
    logic.pwdCtrl.text = 'password2';
    expect(logic.fieldError(RecoveryField.confirmation), isNull);
    expect(api.requests, isEmpty);
    expect(EasyLoading.isShow, isFalse);
  });

  testWidgets('submitting an incomplete form reveals errors without a toast',
      (tester) async {
    final logic = await _mount(tester);
    await logic.nextStep();
    expect(logic.fieldError(RecoveryField.phone), StrRes.plsEnterPhoneNumber);
    expect(
        logic.fieldError(RecoveryField.code), StrRes.plsEnterVerificationCode);
    expect(logic.fieldError(RecoveryField.password), StrRes.plsEnterPassword);
    expect(logic.fieldError(RecoveryField.confirmation), isNotNull);
    expect(api.requests, isEmpty);
    expect(EasyLoading.isShow, isFalse);
  });

  testWidgets('reset business errors remain a form message with fields intact',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _phase(api.verificationStarted.future, 'verification request');
      api.verification.complete(api.response());
      await _phase(api.resetStarted.future, 'reset request');
      api.reset.complete(api.response(code: 20007));
      await _phase(pending, 'reset business error');
    });
    expect(logic.formError, '20007'.tr);
    expect(logic.pwdCtrl.text, 'password1');
    expect(logic.pwdAgainCtrl.text, 'password1');
    expect(logic.submitting.value, isFalse);
    expect(logic.fieldError(RecoveryField.password), isNull);
    expect(EasyLoading.isShow, isFalse);
    expect(Get.currentRoute, AppRoutes.forgetPassword);
  });

  testWidgets('connection failure uses the current language form message',
      (tester) async {
    final logic = await _mount(tester);
    _validFields(logic);
    api.failConnection = true;
    await tester.runAsync(() async {
      await _phase(logic.nextStep(), 'connection failure');
    });
    final chinese = logic.formError;
    expect(chinese, isNotNull);
    expect(chinese, isNot(contains('Internal offline transport detail')));
    Get.locale = const Locale('en', 'US');
    expect(logic.formError, isNot(chinese));
    expect(EasyLoading.isShow, isFalse);
    expect(api.requests, hasLength(1));
  });
}
