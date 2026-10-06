import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/pages/login/login_view.dart';
import 'package:openim/services/auth_credentials/auth_credentials_store.dart';
import 'package:openim/widgets/auth/auth_reference.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _fontLoaded = false;

Future<void> _loadFont() async {
  var font = File('C:/Windows/Fonts/msyh.ttc');
  // Use the SDK's real Roboto font on other test hosts, rather than Ahem's
  // square glyphs, when checking enlarged translated text.
  if (!await font.exists()) {
    var directory = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 6; i++) {
      final candidate =
          File('${directory.path}/material_fonts/roboto-regular.ttf');
      if (await candidate.exists()) {
        font = candidate;
        break;
      }
      directory = directory.parent;
    }
  }
  if (await font.exists()) {
    await (FontLoader('LoginFeedbackFont')
          ..addFont(font.readAsBytes().then(ByteData.sublistView)))
        .load();
    _fontLoaded = true;
  }
}

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Login extends LoginLogic {
  _Login() : super(credentialsStore: AuthCredentialsStore());
  Object? sendError;
  @override
  void getPackageInfo() {}

  @override
  Future<bool> sendVerificationCode() async {
    if (sendError != null) throw sendError!;
    return false;
  }
}

Finder _field(TextEditingController controller) => find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller == controller);

Future<_Login> _mount(WidgetTester tester,
    {Size size = const Size(375, 812),
    Locale locale = const Locale('en', 'US'),
    double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final logic = (await tester.runAsync(() async {
    final controller = Get.put<LoginLogic>(_Login(), permanent: true) as _Login;
    await Future<void>.value();
    return controller;
  }))!;
  await tester.pumpWidget(GetMaterialApp(
    locale: locale,
    translations: TranslationService(),
    theme: ThemeData(fontFamily: _fontLoaded ? 'LoginFeedbackFont' : null),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: LoginPage(),
  ));
  await tester.pump();
  return logic;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await DataSp.init();
    Get.put<IMController>(_IM(), permanent: true);
  });
  tearDown(Get.reset);

  testWidgets(
      'fields validate on blur, then update while the user corrects them',
      (tester) async {
    final logic = await _mount(tester);
    await tester.enterText(_field(logic.phoneCtrl), 'user@');
    expect(logic.accountError, isNull);
    await _tap(tester, _field(logic.pwdCtrl));
    expect(logic.accountError, StrRes.plsEnterRightEmail);
    expect(find.text(StrRes.plsEnterRightEmail), findsOneWidget);
    expect(logic.passwordError, isNull);

    await tester.enterText(_field(logic.phoneCtrl), 'user@example.com');
    expect(logic.accountError, isNull);
    expect(logic.passwordError, StrRes.plsEnterPassword);
    await tester.enterText(_field(logic.pwdCtrl), 'short');
    expect(logic.passwordError, isNull);
    expect(logic.enabled.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SMS send validates only phone and code errors appear after blur',
      (tester) async {
    final logic = await _mount(tester);
    await _tap(tester, find.byKey(const ValueKey('login-mode-switch')));
    await _tap(tester, find.text('Get code'));
    expect(logic.accountError, StrRes.plsEnterPhoneNumber);
    expect(logic.codeError, isNull);
    expect(find.text(StrRes.plsEnterPhoneNumber), findsOneWidget);

    await tester.enterText(_field(logic.phoneCtrl), '13800138000');
    expect(logic.accountError, isNull);
    await tester.enterText(_field(logic.verificationCodeCtrl), '12');
    expect(logic.codeError, isNull);
    await _tap(tester, _field(logic.phoneCtrl));
    expect(logic.codeError, 'Please enter the 6-digit verification code');
    await tester.enterText(_field(logic.verificationCodeCtrl), '123456');
    expect(logic.codeError, isNull);
    await _tap(tester, find.byKey(const ValueKey('login-mode-switch')));
    expect(logic.accountError, isNull);
    expect(logic.passwordError, isNull);
    expect(logic.codeError, isNull);
    expect(logic.phoneCtrl.text, '13800138000');
    expect(logic.verificationCodeCtrl.text, '123456');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'submission reveals all active missing fields without a form error',
      (tester) async {
    final logic = await _mount(tester);
    await tester.runAsync(logic.login);
    await tester.pump();
    expect(logic.accountError, StrRes.plsEnterAccount);
    expect(logic.passwordError, StrRes.plsEnterPassword);
    expect(logic.codeError, isNull);
    expect(logic.formError, isNull);
    expect(find.text(StrRes.plsEnterAccount), findsOneWidget);
    expect(find.text(StrRes.plsEnterPassword), findsOneWidget);
    expect(logic.submitting.value, isFalse);
  });

  testWidgets('visible field errors change language without editing',
      (tester) async {
    final logic = await _mount(tester, locale: const Locale('zh', 'CN'));
    await tester.runAsync(logic.login);
    await tester.pump();
    final chineseAccount = logic.accountError!;
    final chinesePassword = logic.passwordError!;
    expect(find.text(chineseAccount), findsOneWidget);
    expect(find.text(chinesePassword), findsOneWidget);

    await tester.runAsync(() async {
      // Reassembly waits for the frame after its synchronous test warm-up.
      // Start/await its future in the real clock and explicitly deliver it.
      final languageChange = Get.updateLocale(const Locale('en', 'US'))
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await languageChange;
    });
    await tester.pumpAndSettle();
    expect(logic.accountError, isNot(chineseAccount));
    expect(logic.passwordError, isNot(chinesePassword));
    expect(find.text(logic.accountError!), findsOneWidget);
    expect(find.text(logic.passwordError!), findsOneWidget);
    expect(find.text(chineseAccount), findsNothing);
    expect(find.text(chinesePassword), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible form errors keep their cause when the language changes',
      (tester) async {
    final logic = await _mount(tester, locale: const Locale('zh', 'CN'));
    logic.togglePasswordType();
    logic.phoneCtrl.text = '13800138000';
    logic.sendError = (1002, 'backend English failure');
    await tester.runAsync(logic.getVerificationCode);
    await tester.pump();
    final chineseError = logic.formError!;
    expect(find.text(chineseError), findsOneWidget);
    expect(logic.accountError, isNull);
    expect(logic.codeError, isNull);

    await tester.runAsync(() async {
      final languageChange = Get.updateLocale(const Locale('en', 'US'))
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await languageChange;
    });
    await tester.pumpAndSettle();
    expect(logic.formError, isNot(chineseError));
    expect(find.text(logic.formError!), findsOneWidget);
    expect(find.text(chineseError), findsNothing);
    expect(find.textContaining('backend English failure'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remember and recovery share a row with mode switch below button',
      (tester) async {
    await _mount(tester, locale: const Locale('zh', 'CN'));
    final remember =
        tester.getRect(find.byKey(const ValueKey('login-remember-password')));
    final recovery =
        tester.getRect(find.byKey(const ValueKey('login-forgot-password')));
    final button = tester.getRect(find.byKey(const ValueKey('login-submit')));
    final mode =
        tester.getRect(find.byKey(const ValueKey('login-mode-switch')));
    expect(remember.center.dy, recovery.center.dy);
    expect(button.top - remember.bottom, AuthReferenceTokens.buttonGap);
    expect(mode.top, greaterThanOrEqualTo(button.bottom));
    expect(mode.center.dx, button.center.dx);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow English large text wraps the auxiliary actions safely',
      (tester) async {
    await _mount(tester, size: const Size(320, 568), scale: 2);
    await _tap(tester, find.byKey(const ValueKey('login-mode-switch')));
    expect(find.byKey(const ValueKey('login-sms-form')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('login-mode-switch')));
    expect(find.text('Remember password'), findsOneWidget);
    expect(find.text('Forgot password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
