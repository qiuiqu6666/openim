import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/forget_password/forget_password_logic.dart';
import 'package:openim/pages/forget_password/forget_password_view.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/pages/login/login_view.dart';
import 'package:openim/pages/mine/language_setup/language_setup_binding.dart';
import 'package:openim/pages/mine/language_setup/language_setup_view.dart';
import 'package:openim/pages/register/register_logic.dart';
import 'package:openim/pages/register/profile/registration_avatar_service.dart';
import 'package:openim/pages/register/register_view.dart';
import 'package:openim/pages/register/rules/register_password_rules.dart';
import 'package:openim/pages/register/set_password/set_password_logic.dart';
import 'package:openim/pages/register/set_password/set_password_view.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/services/auth_credentials/auth_credentials_store.dart';
import 'package:openim/widgets/auth/auth_reference.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _previewDirectory = String.fromEnvironment('AUTH_PREVIEW_DIR');
bool _hasCjkFont = false;
late Uint8List _avatarBytes;

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Login extends LoginLogic {
  _Login() : super(credentialsStore: AuthCredentialsStore());
  int submissions = 0;

  @override
  void getPackageInfo() {
    displayVersion.value = '3.8.3';
    versionInfo.value = '99Chat 3.8.3';
  }

  @override
  Future<void> login() async => submissions++;

  @override
  Future<bool> sendVerificationCode() async => false;
}

class _Register extends RegisterLogic {
  int submissions = 0;
  bool navigateToProfile = false;

  @override
  Future<void> next() async {
    submissions++;
    if (navigateToProfile) {
      AppNavigator.startSetPassword(
        areaCode: areaCode.value,
        phoneNumber: phone,
        email: email,
        usedFor: 1,
        verificationCode: verificationCodeCtrl.text,
        password: pwdCtrl.text,
      );
    }
  }

  @override
  Future<bool> requestVerificationCode() async => false;
}

class _Forget extends ForgetPasswordLogic {
  int submissions = 0;

  @override
  Future<void> nextStep() async => submissions++;

  @override
  Future<bool> sendVerificationCode() async => false;
}

class _Profile extends SetPasswordLogic {
  int submissions = 0;
  int avatarRequests = 0;

  @override
  // Routed arguments are covered by registration flow tests.
  // ignore: must_call_super
  void onInit() {
    credentialPasswordProvided = true;
    areaCode = '+86';
    phoneNumber = '13800138000';
    email = null;
    verificationCode = '123456';
    usedFor = 1;
    pwdCtrl.text = 'password1';
    pwdAgainCtrl.text = 'password1';
    nicknameCtrl.addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    final nickname = nicknameCtrl.text.trim();
    nicknameError.value =
        nickname.isNotEmpty && nickname.length < 2 ? '昵称至少需要 2 个字符' : null;
    enabled.value = nickname.length >= 2 &&
        RegisterPasswordRules.valid(pwdCtrl.text) &&
        pwdAgainCtrl.text == pwdCtrl.text;
  }

  @override
  Future<void> nextStep() async => submissions++;

  @override
  Future<void> pickAvatar() async {
    avatarRequests++;
    avatar.value = RegistrationAvatar(
        path: '/mock/avatar.png', name: 'avatar.png', bytes: _avatarBytes);
  }
}

Finder _field(TextEditingController controller) => find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller == controller);

Finder get _submit => find.byType(AuthPrimaryButton);

AuthPrimaryButton _button(WidgetTester tester) =>
    tester.widget<AuthPrimaryButton>(_submit);

Future<void> _mount(
  WidgetTester tester,
  Widget page, {
  bool dark = false,
  Size size = const Size(375, 812),
  double scale = 1,
  double keyboard = 0,
  Locale locale = const Locale('zh', 'CN'),
  GlobalKey? boundaryKey,
  bool namedLogin = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  final brightness = dark ? Brightness.dark : Brightness.light;
  final root = RepaintBoundary(key: boundaryKey, child: page);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    fontSizeResolver: (fontSize, _) => fontSize.toDouble(),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      translations: TranslationService(),
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: brightness,
        fontFamily: _hasCjkFont ? 'AuthPreviewFont' : null,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Styles.c_0089FF,
          brightness: brightness,
          surface: Styles.c_FFFFFF,
        ).copyWith(onSurface: Styles.c_0C1C33),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: namedLogin ? null : root,
      initialRoute: namedLogin ? AppRoutes.login : null,
      getPages: [
        GetPage(
          name: AppRoutes.languageSetup,
          page: LanguageSetupPage.new,
          binding: LanguageSetupBinding(),
        ),
        GetPage(
            name: AppRoutes.login, page: () => namedLogin ? root : LoginPage()),
        GetPage(name: AppRoutes.register, page: RegisterPage.new),
        GetPage(name: AppRoutes.setPassword, page: SetPasswordPage.new),
        GetPage(name: AppRoutes.forgetPassword, page: ForgetPasswordPage.new),
      ],
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _enter(
    WidgetTester tester, TextEditingController controller, String value) async {
  final field = _field(controller);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submit);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _loadFonts() async {
  final font = File('C:/Windows/Fonts/msyh.ttc');
  if (await font.exists()) {
    await (FontLoader('AuthPreviewFont')
          ..addFont(font.readAsBytes().then(ByteData.sublistView)))
        .load();
    _hasCjkFont = true;
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')
        ..addFont(rootBundle
            .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
      .load();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFE6F1FC), BlendMode.src);
  final paint = Paint()..color = const Color(0xFF176AC2);
  canvas.drawCircle(const Offset(44, 30), 16, paint);
  canvas.drawOval(const Rect.fromLTWH(12, 52, 64, 58), paint);
  final picture = recorder.endRecording();
  final avatar = await picture.toImage(88, 88);
  _avatarBytes = (await avatar.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  avatar.dispose();
  picture.dispose();
}

Future<void> _export(WidgetTester tester, GlobalKey key, String name) async {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(image.image, key.currentContext!);
    }
  });
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final rendered = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_previewDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      rendered.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Login login;
  late _Register register;
  late _Forget recovery;
  late _Profile profile;

  setUpAll(_loadFonts);
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await DataSp.init();
    Get.put<IMController>(_IM());
    Get.put<AppController>(_App());
    login = Get.put<LoginLogic>(_Login()) as _Login;
    login.operateType = LoginType.phone;
    register = Get.put<RegisterLogic>(_Register()) as _Register;
    recovery = Get.put<ForgetPasswordLogic>(_Forget()) as _Forget;
    profile = Get.put<SetPasswordLogic>(_Profile()) as _Profile;
  });
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });

  testWidgets('password login exposes account, password and remember choice',
      (tester) async {
    addTearDown(() => _unmount(tester));
    await _mount(tester, LoginPage());
    expect(find.text('你好，'), findsOneWidget);
    expect(find.text('欢迎使用99Chat'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-tab-1')), findsOneWidget);
    expect(find.byType(EditableText), findsNWidgets(2));
    expect(_button(tester).onPressed, isNull);
    final remember =
        tester.getRect(find.byKey(const ValueKey('login-remember-password')));
    final forgot =
        tester.getRect(find.byKey(const ValueKey('login-forgot-password')));
    expect(remember.center.dy, closeTo(forgot.center.dy, 1));
    expect(tester.getRect(find.byKey(const ValueKey('login-mode-switch'))).top,
        greaterThan(tester.getRect(_submit).bottom));
    for (final action in [
      'login-customer-service',
      'login-nodes',
      'login-language'
    ]) {
      final size = tester.getSize(find.byKey(ValueKey(action)));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    final account = tester.widget<EditableText>(_field(login.phoneCtrl));
    expect(account.autofillHints, contains(AutofillHints.username));
    expect(
        tester.widget<EditableText>(_field(login.pwdCtrl)).obscureText, isTrue);
    await _enter(tester, login.phoneCtrl, 'user-id');
    await _enter(tester, login.pwdCtrl, 'password1');
    expect(_button(tester).onPressed, isNotNull);
    final beforeRemember = login.rememberPassword.value;
    await tester.tap(find.text('记住密码'));
    await tester.pumpAndSettle();
    expect(login.rememberPassword.value, !beforeRemember);
    await tester.ensureVisible(find.byTooltip('显示密码'));
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(tester.widget<EditableText>(_field(login.pwdCtrl)).obscureText,
        isFalse);
    await _tapSubmit(tester);
    expect(login.submissions, 1);
    expect(find.text('Version 3.8.3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SMS login formats six digits and preserves phone mode',
      (tester) async {
    addTearDown(() => _unmount(tester));
    await _mount(tester, LoginPage());
    await tester.ensureVisible(find.byKey(const ValueKey('login-mode-switch')));
    await tester.tap(find.byKey(const ValueKey('login-mode-switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-sms-form')), findsOneWidget);
    expect(_field(login.pwdCtrl), findsNothing);
    expect(find.byType(EditableText), findsNWidgets(2));
    final phone = tester.widget<EditableText>(_field(login.phoneCtrl));
    expect(phone.keyboardType, TextInputType.phone);
    expect(
        phone.autofillHints, contains(AutofillHints.telephoneNumberNational));
    final code =
        tester.widget<EditableText>(_field(login.verificationCodeCtrl));
    expect(code.keyboardType, TextInputType.number);
    expect(code.autofillHints, contains(AutofillHints.oneTimeCode));
    await _enter(tester, login.phoneCtrl, '13800138000');
    await _enter(tester, login.verificationCodeCtrl, '12a34567');
    expect(login.verificationCodeCtrl.text, '123456');
    expect(_button(tester).onPressed, isNotNull);
    await _tapSubmit(tester);
    expect(login.submissions, 1);
    await tester.ensureVisible(find.byKey(const ValueKey('login-mode-switch')));
    await tester.tap(find.byKey(const ValueKey('login-mode-switch')));
    await tester.pumpAndSettle();
    expect(_field(login.pwdCtrl), findsOneWidget);
    expect(login.verificationCodeCtrl.text, '123456');
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration first step validates four fields and offers next',
      (tester) async {
    addTearDown(() => _unmount(tester));
    await _mount(tester, RegisterPage());
    expect(find.byType(EditableText), findsNWidgets(4));
    expect(find.byKey(const ValueKey('registration-step-1')), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byType(AuthFormMessage), findsNothing);
    expect(_button(tester).text, '下一步');
    expect(_button(tester).onPressed, isNull);
    expect(tester.widget<EditableText>(_field(register.phoneCtrl)).keyboardType,
        TextInputType.phone);
    await _enter(tester, register.phoneCtrl, '13800138000');
    await _enter(tester, register.verificationCodeCtrl, '123456');
    await _enter(tester, register.pwdCtrl, 'short1');
    await _enter(tester, register.pwdAgainCtrl, 'short1');
    expect(_button(tester).onPressed, isNull);
    await _enter(tester, register.pwdCtrl, 'password1');
    await _enter(tester, register.pwdAgainCtrl, 'password2');
    expect(_button(tester).onPressed, isNull);
    await _enter(tester, register.pwdAgainCtrl, 'password1');
    expect(_button(tester).onPressed, isNotNull);
    await _tapSubmit(tester);
    expect(register.submissions, 1);
    expect(find.byType(RegisterPage), findsOneWidget);
    expect(find.byType(SetPasswordPage), findsNothing);
    expect(
        tester
            .widget<EditableText>(_field(register.pwdAgainCtrl))
            .textInputAction,
        TextInputAction.done);
    await tester.ensureVisible(_field(register.pwdAgainCtrl));
    await tester.tap(_field(register.pwdAgainCtrl));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(register.submissions, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile allows no avatar and previews a picked image',
      (tester) async {
    addTearDown(() => _unmount(tester));
    await _mount(tester, SetPasswordPage());
    expect(find.byKey(const ValueKey('register-profile-step')), findsOneWidget);
    expect(find.byKey(const ValueKey('registration-step-2')), findsOneWidget);
    expect(find.text('选择头像'), findsOneWidget);
    expect(find.text('上一步'), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
    expect(_field(profile.nicknameCtrl), findsOneWidget);
    expect(_field(profile.pwdCtrl), findsNothing);
    expect(_field(profile.pwdAgainCtrl), findsNothing);
    expect(_button(tester).onPressed, isNull);
    await _enter(tester, profile.nicknameCtrl, 'A');
    expect(_button(tester).onPressed, isNull);
    await _enter(tester, profile.nicknameCtrl, '测试用户');
    expect(_button(tester).onPressed, isNotNull);
    expect(profile.avatar.value, isNull);
    await _tapSubmit(tester);
    expect(profile.submissions, 1);
    await tester.ensureVisible(
        find.byKey(const ValueKey('registration-avatar-action')));
    await tester.tap(find.byKey(const ValueKey('registration-avatar-action')));
    await tester.pumpAndSettle();
    expect(profile.avatarRequests, 1);
    expect(find.text('更换头像'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(
        find.byKey(const ValueKey('registration-avatar-preview')));
    expect(avatar.backgroundImage, isA<MemoryImage>());
    expect((avatar.backgroundImage! as MemoryImage).bytes, _avatarBytes);
    profile.pickingAvatar.value = true;
    await tester.pump();
    expect(_button(tester).onPressed, isNull);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('registration-avatar-action')))
            .onPressed,
        isNull);
    profile.pickingAvatar.value = false;
    profile.accountCreated.value = true;
    profile.avatarUploadFailed.value = true;
    await tester.pump();
    expect(_button(tester).text, '重试上传头像');
    expect(_button(tester).onPressed, isNotNull);
    expect(tester.widget<EditableText>(_field(profile.nicknameCtrl)).readOnly,
        isTrue);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('register-profile-back')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('registration-avatar-action')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recovery is a four-field form with independent password toggles',
      (tester) async {
    addTearDown(() => _unmount(tester));
    await _mount(tester, ForgetPasswordPage());
    expect(find.byType(EditableText), findsNWidgets(4));
    expect(find.text('找回密码'), findsOneWidget);
    expect(find.text('重置密码'), findsOneWidget);
    expect(_button(tester).onPressed, isNull);
    await _enter(tester, recovery.phoneCtrl, '13800138000');
    await _enter(tester, recovery.verificationCodeCtrl, '12a34567');
    expect(recovery.verificationCodeCtrl.text, '123456');
    await _enter(tester, recovery.pwdCtrl, 'password1');
    await _enter(tester, recovery.pwdAgainCtrl, 'password2');
    expect(_button(tester).onPressed, isNull);
    await _enter(tester, recovery.pwdAgainCtrl, 'password1');
    expect(_button(tester).onPressed, isNotNull);
    final toggles = find.byTooltip('显示密码');
    expect(toggles, findsNWidgets(2));
    await tester.ensureVisible(toggles.first);
    await tester.tap(toggles.first);
    await tester.pump();
    expect(tester.widget<EditableText>(_field(recovery.pwdCtrl)).obscureText,
        isFalse);
    expect(
        tester.widget<EditableText>(_field(recovery.pwdAgainCtrl)).obscureText,
        isTrue);
    await _tapSubmit(tester);
    expect(recovery.submissions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language picker changes copy without clearing login inputs',
      (tester) async {
    addTearDown(() => _unmount(tester));
    await _mount(tester, LoginPage());
    await _enter(tester, login.phoneCtrl, 'user-id');
    await _enter(tester, login.pwdCtrl, 'password1');
    await tester.ensureVisible(find.byKey(const ValueKey('login-language')));
    await tester.tap(find.byKey(const ValueKey('login-language')));
    await tester.pumpAndSettle();
    expect(find.byType(LanguageSetupPage), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text(StrRes.english));
      // Get's application reassembly must complete outside the fake frame.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    Get.back();
    await tester.pumpAndSettle();
    expect(login.phoneCtrl.text, 'user-id');
    expect(login.pwdCtrl.text, 'password1');
    expect(find.text('Welcome to 99Chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register tab and back preserve the existing login draft',
      (tester) async {
    addTearDown(() => _unmount(tester));
    await _mount(tester, LoginPage(), namedLogin: true);
    await _enter(tester, login.phoneCtrl, 'user-id');
    await _enter(tester, login.pwdCtrl, 'password1');
    await tester.tap(find.byKey(const ValueKey('auth-tab-1')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterPage), findsOneWidget);
    await _enter(tester, register.phoneCtrl, '13800138000');
    await _enter(tester, register.verificationCodeCtrl, '123456');
    await _enter(tester, register.pwdCtrl, 'password1');
    await _enter(tester, register.pwdAgainCtrl, 'password1');
    await tester.ensureVisible(find.byKey(const ValueKey('auth-tab-0')));
    await tester.tap(find.byKey(const ValueKey('auth-tab-0')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(login.phoneCtrl.text, 'user-id');
    expect(login.pwdCtrl.text, 'password1');
    expect(register.phoneCtrl.text, '13800138000');
    expect(register.pwdCtrl.text, 'password1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile back preserves the first step credentials',
      (tester) async {
    addTearDown(() => _unmount(tester));
    register.navigateToProfile = true;
    await _mount(tester, RegisterPage());
    await _enter(tester, register.phoneCtrl, '13800138000');
    await _enter(tester, register.verificationCodeCtrl, '123456');
    await _enter(tester, register.pwdCtrl, 'password1');
    await _enter(tester, register.pwdAgainCtrl, 'password1');
    await _tapSubmit(tester);
    expect(find.byType(SetPasswordPage), findsOneWidget);
    expect(find.byKey(const ValueKey('registration-step-2')), findsOneWidget);
    await _enter(tester, profile.nicknameCtrl, '测试用户');
    await tester
        .ensureVisible(find.byKey(const ValueKey('register-profile-back')));
    await tester.tap(find.byKey(const ValueKey('register-profile-back')));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterPage), findsOneWidget);
    expect(find.byType(EditableText), findsNWidgets(4));
    expect(register.phoneCtrl.text, '13800138000');
    expect(register.verificationCodeCtrl.text, '123456');
    expect(register.pwdCtrl.text, 'password1');
    expect(register.pwdAgainCtrl.text, 'password1');
    expect(profile.submissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference forms remain scrollable on compact and keyboard views',
      (tester) async {
    addTearDown(() => _unmount(tester));
    final pages = <Widget Function()>[
      LoginPage.new,
      RegisterPage.new,
      SetPasswordPage.new,
      ForgetPasswordPage.new,
    ];
    final scenarios = [
      (size: const Size(320, 640), dark: false, scale: 1.0, keyboard: 0.0),
      (size: const Size(375, 812), dark: true, scale: 1.0, keyboard: 0.0),
      (size: const Size(844, 390), dark: false, scale: 1.0, keyboard: 0.0),
      (size: const Size(1000, 800), dark: false, scale: 1.0, keyboard: 0.0),
      (size: const Size(375, 812), dark: true, scale: 2.0, keyboard: 280.0),
    ];
    for (final scenario in scenarios) {
      for (final page in pages) {
        await _mount(tester, page(),
            size: scenario.size,
            dark: scenario.dark,
            scale: scenario.scale,
            keyboard: scenario.keyboard);
        expect(tester.takeException(), isNull, reason: '$page at $scenario');
        final scroll = find.byType(SingleChildScrollView).first;
        await tester.drag(scroll, const Offset(0, -1000));
        await tester.pumpAndSettle();
        final rect = tester.getRect(_submit);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom,
            lessThanOrEqualTo(scenario.size.height - scenario.keyboard + 1));
        final field = find.byType(EditableText).first;
        expect(Theme.of(tester.element(field)).brightness, Brightness.light);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('export actual reference authentication screens', (tester) async {
    addTearDown(() => _unmount(tester));
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final dark in [false, true]) {
        for (final name in [
          'login-password',
          'login-sms',
          'register',
          'register-profile',
          'register-profile-selected',
          'register-profile-retry',
          'recovery'
        ]) {
          final sms = name == 'login-sms';
          if (login.isPasswordLogin.value == sms) login.togglePasswordType();
          final page = switch (name) {
            'login-password' || 'login-sms' => LoginPage(),
            'register' => RegisterPage(),
            'register-profile' ||
            'register-profile-selected' ||
            'register-profile-retry' =>
              SetPasswordPage(),
            _ => ForgetPasswordPage(),
          };
          if (name.startsWith('register-profile')) {
            final selected = name != 'register-profile';
            profile.avatar.value = selected
                ? RegistrationAvatar(
                    path: '/mock/avatar.png',
                    name: 'avatar.png',
                    bytes: _avatarBytes)
                : null;
            profile.nicknameCtrl.text = selected ? '示例用户' : '';
            profile.accountCreated.value = name == 'register-profile-retry';
            profile.avatarUploadFailed.value = name == 'register-profile-retry';
          }
          final key = GlobalKey();
          await _mount(tester, page, dark: dark, boundaryKey: key);
          await _export(tester, key, '$name-${dark ? 'app-dark' : 'light'}');
          if (name == 'register') {
            await tester.drag(find.byType(SingleChildScrollView).first,
                const Offset(0, -1000));
            await tester.pumpAndSettle();
            final viewport =
                tester.getRect(find.byType(SingleChildScrollView).first);
            final button = tester.getRect(_submit);
            expect(button.top, greaterThanOrEqualTo(viewport.top));
            expect(button.bottom, lessThanOrEqualTo(viewport.bottom));
            await _export(
                tester, key, '$name-scrolled-${dark ? 'app-dark' : 'light'}');
          }
          if (name == 'login-password' ||
              name == 'login-sms' ||
              name == 'register' ||
              name == 'recovery') {
            final field = find.byType(EditableText).first;
            await tester.ensureVisible(field);
            tester.widget<EditableText>(field).focusNode.requestFocus();
            await tester.pumpAndSettle();
            await _export(
                tester, key, '$name-focused-${dark ? 'app-dark' : 'light'}');
          }
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      debugDisableShadows = oldShadows;
    }
  }, skip: _previewDirectory.isEmpty);

  testWidgets('export field errors after actual typing and blur',
      (tester) async {
    addTearDown(() => _unmount(tester));
    for (final name in [
      'login-password-error',
      'register-error',
      'recovery-error'
    ]) {
      if (name != 'login-password-error') login.operateType = LoginType.phone;
      final page = switch (name) {
        'login-password-error' => LoginPage(),
        'register-error' => RegisterPage(),
        _ => ForgetPasswordPage(),
      };
      final controls = switch (name) {
        'login-password-error' => [login.phoneCtrl, login.pwdCtrl],
        'register-error' => [
            register.phoneCtrl,
            register.verificationCodeCtrl,
            register.pwdCtrl,
            register.pwdAgainCtrl,
          ],
        _ => [
            recovery.phoneCtrl,
            recovery.verificationCodeCtrl,
            recovery.pwdCtrl,
            recovery.pwdAgainCtrl,
          ],
      };
      final values = switch (name) {
        'login-password-error' => ['bad@', ''],
        'register-error' => ['123', '12', 'short1', 'short2'],
        _ => ['123', '12', 'short1', 'short2'],
      };
      final key = GlobalKey();
      await _mount(tester, page, boundaryKey: key);
      for (var i = 0; i < controls.length; i++) {
        await _enter(tester, controls[i], values[i]);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // Return to the top so these previews show the first field's guidance.
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _export(tester, key, name);
    }
  }, skip: _previewDirectory.isEmpty);
}
