import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/pages/register/register_logic.dart';
import 'package:openim/pages/register/set_password/set_password_logic.dart';
import 'package:openim/pages/register/register_view.dart';
import 'package:openim/pages/register/rules/registration_field.dart';
import 'package:openim/pages/register/widgets/register_reference_widgets.dart';
import 'package:openim/services/auth_credentials/auth_credentials_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  Future<void> autoCheckVersionUpgrade() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credentials extends AuthCredentialsStore {
  @override
  Future<StoredAuthCredentials> load() async => const StoredAuthCredentials();
}

class _Login extends LoginLogic {
  _Login() : super(credentialsStore: _Credentials());
  @override
  void getPackageInfo() {}
}

class _Register extends RegisterLogic {
  int checks = 0;
  Object? failure = (20006, 'English verification details');
  _DirectRegistration? submitted;

  @override
  SetPasswordLogic createRegistration(Map<String, dynamic> arguments) =>
      submitted = _DirectRegistration(arguments);

  @override
  Future<void> verifyCredentials({
    required String areaCode,
    String? phoneNumber,
    String? email,
    required String verificationCode,
    String? invitationCode,
  }) async {
    checks++;
    if (failure != null) throw failure!;
  }
}

class _DirectRegistration extends SetPasswordLogic {
  _DirectRegistration(Map<String, dynamic> arguments)
      : super(initialArguments: arguments);
  int attempts = 0;
  @override
  Future<void> register() async {
    attempts++;
    accountCreated.value = true;
  }
}

Finder _field(TextEditingController controller) => find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller == controller);

void _fillValid(_Register logic) {
  logic.phoneCtrl.text = '13800138000';
  logic.verificationCodeCtrl.text = '123456';
  logic.pwdCtrl.text = 'password1';
  logic.pwdAgainCtrl.text = 'password1';
}

void main() {
  late _Register logic;

  setUp(() async {
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Get.put<IMController>(_IM(), permanent: true);
    Get.put<AppController>(_App(), permanent: true);
    Get.put<LoginLogic>(_Login(), permanent: true);
    logic = Get.put<RegisterLogic>(_Register()) as _Register;
  });
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
  });

  testWidgets('one-step registration submits without a profile or avatar page',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: RegisterPage()));
    logic.failure = null;
    _fillValid(logic);
    await logic.next();
    await tester.pump();
    final submission = logic.submitted!;
    expect(submission.nicknameCtrl.text, '99Chat用户');
    expect(submission.avatar.value, isNull);
    expect(submission.pwdCtrl.text, 'password1');
    expect(submission.verificationCode, logic.verificationCodeCtrl.text);
    expect(submission.attempts, 1);
    expect(find.byType(RegisterPage), findsOneWidget);
    // A login retry must not verify or create the account again.
    await logic.next();
    expect(logic.checks, 1);
    expect(identical(logic.submitted, submission), isTrue);
    expect(submission.attempts, 2);
  });

  testWidgets('registration switches identity and clears the previous code',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: RegisterPage()));
    _fillValid(logic);
    await tester.tap(find.byKey(const ValueKey('auth-identity-email')));
    await tester.pump();
    expect(logic.phone, isNull);
    expect(logic.verificationCodeCtrl.text, isEmpty);
    logic.phoneCtrl.text = 'new@example.test';
    expect(logic.email, 'new@example.test');
    await tester.tap(find.byKey(const ValueKey('auth-identity-phone')));
    await tester.pump();
    expect(logic.email, isNull);
    expect(logic.phoneCtrl.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('registration reveals local errors on blur and updates on edits',
      (tester) async {
    logic.phoneCtrl.text = '123';
    expect(logic.errorFor(RegistrationField.account), isNull);
    await tester.pumpWidget(GetMaterialApp(home: RegisterPage()));
    expect(find.text('手机注册'), findsOneWidget);
    expect(find.text('邮箱注册'), findsOneWidget);
    await tester.tap(_field(logic.phoneCtrl));
    await tester.pump();
    await tester.ensureVisible(_field(logic.verificationCodeCtrl));
    await tester.pumpAndSettle();
    await tester.tap(_field(logic.verificationCodeCtrl));
    await tester.pump();
    expect(
        logic.errorFor(RegistrationField.account), StrRes.plsEnterRightPhone);
    expect(find.text(StrRes.plsEnterRightPhone), findsOneWidget);
    logic.phoneCtrl.text = '13800138000';
    await tester.pump();
    expect(logic.errorFor(RegistrationField.account), isNull);
    expect(find.text(StrRes.plsEnterRightPhone), findsNothing);
    expect(logic.checks, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalid submission marks fields without making a request',
      (tester) async {
    await logic.next();
    for (final field in [
      RegistrationField.account,
      RegistrationField.code,
      RegistrationField.password,
      RegistrationField.confirmation,
    ]) {
      expect(logic.errorFor(field), isNotNull);
    }
    expect(EasyLoading.isShow, isFalse);
    expect(logic.checks, 0);
    _fillValid(logic);
    for (final field in [
      RegistrationField.account,
      RegistrationField.code,
      RegistrationField.password,
      RegistrationField.confirmation,
    ]) {
      expect(logic.errorFor(field), isNull);
    }
  });

  testWidgets('verification errors use the shared alert in the current locale',
      (tester) async {
    await tester.pumpWidget(
        GetMaterialApp(builder: EasyLoading.init(), home: RegisterPage()));
    _fillValid(logic);
    await logic.next();
    await tester.pumpAndSettle();
    expect(logic.checks, 1);
    final chinese =
        HttpUtil.errorMessage(logic.failure!, path: Urls.checkVerificationCode);
    expect(find.text(chinese), findsOneWidget);
    expect(find.byType(AppAlertDialog<void>), findsOneWidget);
    expect(find.textContaining('English verification details'), findsNothing);
    expect(logic.errorFor(RegistrationField.code), isNull);
    await tester.tap(find.text(StrRes.determine));
    await tester.pumpAndSettle();
    Get.locale = const Locale('en', 'US');
    await logic.next();
    await tester.pumpAndSettle();
    final english =
        HttpUtil.errorMessage(logic.failure!, path: Urls.checkVerificationCode);
    expect(english, isNot(chinese));
    expect(find.text(english), findsOneWidget);
    expect(logic.pwdCtrl.text, 'password1');
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('password hints only appear for nonempty invalid input',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: RegisterPage()));
    final checklist = find.byType(RegisterPasswordChecklist);
    expect(find.text('8–24 位'), findsNothing);
    for (final value in ['a', 'a1']) {
      logic.pwdCtrl.text = value;
      await tester.pump();
      expect(find.text('8–24 位'), findsOneWidget);
    }
    for (final value in ['password1', '']) {
      logic.pwdCtrl.text = value;
      await tester.pump();
      expect(find.text('8–24 位'), findsNothing);
    }
    logic.pwdCtrl.text = 'a';
    logic.touchField(RegistrationField.password);
    await tester.pump();
    expect(tester.widget<RegisterPasswordChecklist>(checklist).showInvalid,
        isTrue);
    expect(find.text('8–24 位'), findsOneWidget);
    expect(find.text('英文字母'), findsOneWidget);
    expect(find.text('数字'), findsOneWidget);
    expect(find.text('至少 8 位，须同时包含英文字母和数字'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'password visibility has labelled tap targets and locks while busy',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: RegisterPage()));
    final toggles = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '显示密码');
    expect(toggles, findsNWidgets(2));
    for (final toggle in toggles.evaluate()) {
      final size = tester.getSize(find.byWidget(toggle.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    logic.submitting.value = true;
    await tester.pump();
    for (final toggle in tester.widgetList<IconButton>(toggles)) {
      expect(toggle.onPressed, isNull);
    }
    expect(logic.obscurePassword.value, isTrue);
    expect(logic.obscureConfirmPassword.value, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('registration submit remains reachable at 375 by 812',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GetMaterialApp(home: RegisterPage()));
    await tester.ensureVisible(find.byKey(const ValueKey('register-submit')));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final button =
        tester.getRect(find.byKey(const ValueKey('register-submit')));
    expect(button.top, greaterThanOrEqualTo(viewport.top));
    expect(button.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
