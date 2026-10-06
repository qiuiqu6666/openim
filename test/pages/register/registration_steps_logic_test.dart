import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/pages/register/profile/registration_avatar_service.dart';
import 'package:openim/pages/register/profile/registration_profile_draft.dart';
import 'package:openim/pages/register/rules/registration_field.dart';
import 'package:openim/pages/register/set_password/set_password_logic.dart';
import 'package:openim/pages/register/verify_phone/verify_phone_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  int logins = 0;

  @override
  Future<void> login(String account, String token) async {
    logins++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Login extends LoginLogic {
  @override
  void getPackageInfo() {}
}

class _Cache extends GetxController implements CacheController {
  @override
  void resetCache() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AvatarSelection extends RegistrationAvatarService {
  _AvatarSelection(this.selected);
  final RegistrationAvatar selected;

  @override
  Future<RegistrationAvatar?> pick() async => selected;
}

class _Verify extends VerifyPhoneLogic {
  // Create the pending response in the same zone as its request. A completer
  // created before runAsync schedules completion back into the test fake clock.
  Completer<void>? _response;
  Completer<void> get response => _response ??= Completer<void>();
  int checks = 0;
  String? checkedCode;

  @override
  Future<void> checkVerificationCode(String verificationCode) {
    checks++;
    checkedCode = verificationCode;
    return response.future;
  }
}

class _HTTP implements HttpClientAdapter {
  Completer<ResponseBody>? _response;
  int requests = 0;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    requests++;
    lastRequest = options;
    return (_response ??= Completer<ResponseBody>()).future;
  }

  void respond({bool withTokens = false, int error = 0}) =>
      _response!.complete(ResponseBody.fromString(
          jsonEncode({
            'errCode': error,
            'errMsg': error == 0 ? '' : 'NicknameAlreadyUsed',
            'data': {
              'userID': 'new-user',
              'chatToken': withTokens ? 'new-chat' : '',
              'imToken': withTokens ? 'new-im' : '',
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          }));
}

Widget _app() => MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(initialEntries: [
          OverlayEntry(
            builder: (_) => GetMaterialApp(
              initialRoute: '/',
              builder: EasyLoading.init(),
              getPages: [
                GetPage(
                    name: '/',
                    page: () => const Scaffold(body: Text('auth entry'))),
                GetPage(
                    name: AppRoutes.login,
                    page: () => const Scaffold(body: Text('login form'))),
                GetPage(
                    name: AppRoutes.home,
                    page: () => const Scaffold(body: Text('main ready'))),
                GetPage(
                    name: AppRoutes.verifyPhone,
                    page: () => const Scaffold(body: Text('verify form'))),
                GetPage(
                    name: AppRoutes.setPassword,
                    page: () => const Scaffold(body: Text('password form'))),
              ],
            ),
          ),
        ]),
      ),
    );

const _arguments = {
  'phoneNumber': '13800138000',
  'email': null,
  'areaCode': '+86',
  'usedFor': 1,
  'verificationCode': '123456',
  'invitationCode': null,
  'password': 'password1',
};

Future<void> _flushUntil(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

Future<_Verify> _openVerification(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  Get.toNamed(AppRoutes.verifyPhone, arguments: _arguments);
  await tester.pumpAndSettle();
  return Get.put<VerifyPhoneLogic>(_Verify()) as _Verify;
}

Future<SetPasswordLogic> _openPassword(WidgetTester tester,
    {bool withPassword = true,
    RegistrationProfileDraft? profileDraft,
    RegistrationAvatarService? avatarService}) async {
  await tester.pumpWidget(_app());
  Get.toNamed(AppRoutes.setPassword, arguments: {
    ..._arguments,
    if (!withPassword) 'password': null,
    'profileDraft': profileDraft,
  });
  await tester.pumpAndSettle();
  final logic = Get.put(SetPasswordLogic(avatarService: avatarService));
  logic.nicknameCtrl.text = '  Alice  ';
  return logic;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _HTTP adapter;
  late _IM im;

  setUp(() async {
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    im = Get.put<IMController>(_IM(), permanent: true) as _IM;
    Get.put<LoginLogic>(_Login(), permanent: true);
    Get.put<CacheController>(_Cache(), permanent: true);
    http.dio = Dio();
    HttpUtil.init();
    adapter = _HTTP();
    http.dio.httpClientAdapter = adapter;
  });

  tearDown(() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    http.dio.close(force: true);
    Get.reset();
  });

  testWidgets('only six digits enable and submit registration verification',
      (tester) async {
    final logic = await _openVerification(tester);
    for (final code in ['', '12345', '1234567', 'abcdef', '12345a']) {
      logic.codeEditCtrl.text = code;
      expect(logic.enabled.value, isFalse);
      await logic.completed(code);
    }
    expect(logic.checks, 0);
    expect(logic.submitting.value, isFalse);
    logic.codeEditCtrl.text = '123456';
    expect(logic.enabled.value, isTrue);
  });

  testWidgets('registration verification submits once and opens passwords',
      (tester) async {
    final logic = await _openVerification(tester);
    await tester.runAsync(() async {
      final pending = logic.completed('123456');
      expect(logic.submitting.value, isTrue);
      await _flushUntil(() => logic.checks == 1);
      await logic.completed('654321');
      expect(logic.checks, 1);
      logic.response.complete();
      await pending;
    });
    await tester.pumpAndSettle();
    expect(logic.checkedCode, '123456');
    expect(find.text('password form'), findsOneWidget);
    expect(Get.arguments['verificationCode'], '123456');
  });

  testWidgets('leaving before verification starts prevents its request',
      (tester) async {
    final logic = await _openVerification(tester);
    await tester.runAsync(() async {
      final pending = logic.completed('123456');
      await Get.delete<VerifyPhoneLogic>(force: true);
      await pending;
    });
    await tester.pumpAndSettle();
    expect(logic.checks, 0);
    expect(find.text('verify form'), findsOneWidget);
  });

  for (final success in [true, false]) {
    testWidgets(
        'closed registration verification ignores late success=$success',
        (tester) async {
      final logic = await _openVerification(tester);
      await tester.runAsync(() async {
        final pending = logic.completed('123456');
        await _flushUntil(() => logic.checks == 1);
        await Get.delete<VerifyPhoneLogic>(force: true);
        if (success) {
          logic.response.complete();
        } else {
          logic.response.completeError(StateError('expired code'));
        }
        await pending;
      });
      await tester.pumpAndSettle();
      expect(logic.codeErrorCtrl.isClosed, isTrue);
      expect(find.text('verify form'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('verification failure releases submission and signals the form',
      (tester) async {
    final logic = await _openVerification(tester);
    final errors = <ErrorAnimationType>[];
    final subscription = logic.codeErrorCtrl.stream.listen(errors.add);
    addTearDown(subscription.cancel);
    await tester.runAsync(() async {
      final pending = logic.completed('123456');
      await _flushUntil(() => logic.checks == 1);
      logic.response.completeError(StateError('expired code'));
      await pending;
    });
    await tester.pump();
    expect(logic.submitting.value, isFalse);
    expect(errors, [ErrorAnimationType.shake]);
    expect(find.text('verify form'), findsOneWidget);
  });

  testWidgets('invalid or mismatched signup passwords never register',
      (tester) async {
    final logic = await _openPassword(tester);
    logic.pwdCtrl.text = 'short';
    logic.pwdAgainCtrl.text = 'short';
    await logic.nextStep();
    logic.pwdCtrl.text = 'password1';
    logic.pwdAgainCtrl.text = 'password2';
    await logic.nextStep();
    expect(adapter.requests, 0);
    expect(logic.submitting.value, isFalse);
  });

  testWidgets('profile consumes the password snapshot and requires a nickname',
      (tester) async {
    final logic = await _openPassword(tester);
    expect(logic.credentialPasswordProvided, isTrue);
    expect(logic.pwdCtrl.text, _arguments['password']);
    expect(logic.pwdAgainCtrl.text, _arguments['password']);
    for (final nickname in ['', ' ', 'A']) {
      logic.nicknameCtrl.text = nickname;
      expect(logic.enabled.value, isFalse);
      await logic.nextStep();
    }
    expect(logic.nicknameError.value, isNotNull);
    expect(adapter.requests, 0);
    logic.nicknameCtrl.text = 'Alice';
    expect(logic.enabled.value, isTrue);
    expect(logic.nicknameError.value, isNull);
    logic.pwdCtrl.clear();
    expect(logic.credentialPasswordProvided, isTrue);
  });

  testWidgets('profile nickname validation waits for blur and clears on edit',
      (tester) async {
    final logic = await _openPassword(tester);
    logic.nicknameCtrl.text = 'A';
    expect(logic.errorFor(RegistrationField.nickname), isNull);
    logic.touchField(RegistrationField.nickname);
    expect(logic.errorFor(RegistrationField.nickname), isNotNull);
    expect(EasyLoading.isShow, isFalse);
    logic.nicknameCtrl.text = 'Alice';
    expect(logic.errorFor(RegistrationField.nickname), isNull);
    expect(adapter.requests, 0);
  });

  testWidgets(
      'returning to profile restores nickname and selected avatar draft',
      (tester) async {
    final photo = RegistrationAvatar(
        path: 'avatar.png', name: 'avatar.png', bytes: Uint8List(1));
    final draft = RegistrationProfileDraft();
    final logic = await _openPassword(tester,
        profileDraft: draft, avatarService: _AvatarSelection(photo));
    logic.nicknameCtrl.text = 'Bob';
    await logic.pickAvatar();
    expect(draft.nickname, 'Bob');
    expect(draft.avatar, same(photo));
    await Get.delete<SetPasswordLogic>(force: true);
    final reopened = Get.put(SetPasswordLogic());
    expect(reopened.nicknameCtrl.text, 'Bob');
    expect(reopened.avatar.value, same(photo));
    expect(adapter.requests, 0);
  });

  testWidgets('legacy verification can supply passwords without changing mode',
      (tester) async {
    final logic = await _openPassword(tester, withPassword: false);
    expect(logic.credentialPasswordProvided, isFalse);
    expect(logic.pwdCtrl.text, isEmpty);
    expect(logic.enabled.value, isFalse);
    logic.pwdCtrl.text = 'abc1234';
    logic.pwdAgainCtrl.text = 'abc1234';
    expect(logic.enabled.value, isFalse);
    logic.pwdCtrl.text = 'password1';
    logic.pwdAgainCtrl.text = 'password2';
    expect(logic.enabled.value, isFalse);
    logic.pwdAgainCtrl.text = 'password1';
    expect(logic.enabled.value, isTrue);
    expect(logic.credentialPasswordProvided, isFalse);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => adapter.requests == 1);
      adapter.respond(error: 20018);
      await pending;
    });
    expect(adapter.lastRequest!.data['verifyCode'], '123456');
    expect(adapter.lastRequest!.data['user']['password'],
        IMUtils.generateMD5('password1'));
    expect(logic.credentialPasswordProvided, isFalse);
  });

  testWidgets(
      'direct signup validates passwords, contact and verification code',
      (tester) async {
    final logic = await _openPassword(tester);
    logic.pwdCtrl.text = '   ';
    await logic.register();
    logic.pwdCtrl.text = 'password1';
    logic.pwdAgainCtrl.text = '   ';
    await logic.register();
    logic.pwdAgainCtrl.text = 'password1';
    logic.phoneNumber = '   ';
    await logic.register();
    logic.phoneNumber = 'invalid-phone';
    await logic.register();
    logic.phoneNumber = '13800138000';
    logic.verificationCode = '   ';
    await logic.register();
    expect(adapter.requests, 0);
    expect(logic.submitting.value, isFalse);
    expect(im.logins, 0);
  });

  testWidgets('signup is single flight and sends the submitted nickname',
      (tester) async {
    final logic = await _openPassword(tester);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      expect(logic.submitting.value, isTrue);
      await _flushUntil(() => adapter.requests == 1);
      await logic.nextStep();
      expect(adapter.requests, 1);
      logic.nicknameCtrl.text = 'Bob';
      adapter.respond(withTokens: true);
      await pending;
    });
    await tester.pumpAndSettle();
    expect(adapter.lastRequest!.data['user']['nickname'], 'Alice');
    expect(im.logins, 1);
    expect(find.text('main ready'), findsOneWidget);
  });

  for (final language in ['zh', 'en']) {
    testWidgets('signup rejection shows one centered shared toast in $language',
        (tester) async {
      Get.locale = Locale(language);
      var shown = 0;
      void onStatus(EasyLoadingStatus status) {
        if (status == EasyLoadingStatus.show) shown++;
      }

      EasyLoading.addStatusCallback(onStatus);
      addTearDown(() => EasyLoading.removeCallback(onStatus));
      final logic = await _openPassword(tester);
      await tester.runAsync(() async {
        final pending = logic.nextStep();
        await _flushUntil(() => adapter.requests == 1);
        adapter.respond(error: 20018);
        await pending;
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(logic.submitting.value, isFalse);
      expect(logic.nicknameCtrl.text, '  Alice  ');
      expect(logic.pwdCtrl.text, 'password1');
      expect(find.text('password form'), findsOneWidget);
      expect(logic.errorFor(RegistrationField.nickname), isNull);
      final message = HttpUtil.errorMessage((20018, ''), path: Urls.register);
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('NicknameAlreadyUsed'), findsNothing);
      expect(shown, 1);
      final toast = tester.getRect(find.text(message));
      final page =
          tester.getRect(find.widgetWithText(Scaffold, 'password form'));
      expect(toast.center.dx, closeTo(page.center.dx, 1));
      expect(toast.center.dy, closeTo(page.center.dy, 1));
      expect(EasyLoading.isShow, isTrue);
      await EasyLoading.dismiss(animation: false);
      logic.nicknameCtrl.text = 'Bob';
      expect(logic.enabled.value, isTrue);
    });
  }

  testWidgets('late signup rejection does not show a toast after leaving',
      (tester) async {
    final logic = await _openPassword(tester);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => adapter.requests == 1);
      await Get.delete<SetPasswordLogic>(force: true);
      adapter.respond(error: 20018);
      await pending;
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(EasyLoading.isShow, isFalse);
    expect(im.logins, 0);
    expect(find.text('password form'), findsOneWidget);
  });

  testWidgets('late signup credentials cannot authenticate a closed step',
      (tester) async {
    final logic = await _openPassword(tester);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => adapter.requests == 1);
      await Get.delete<SetPasswordLogic>(force: true);
      adapter.respond(withTokens: true);
      await pending;
    });
    await tester.pumpAndSettle();
    expect(DataSp.userID, isNull);
    expect(im.logins, 0);
    expect(find.text('password form'), findsOneWidget);
  });

  testWidgets('late signup cannot replace credentials from another login',
      (tester) async {
    final logic = await _openPassword(tester);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => adapter.requests == 1);
      await DataSp.putLoginCertificate(LoginCertificate.fromJson({
        'userID': 'other-user',
        'chatToken': 'other-chat',
        'imToken': 'other-im',
      }));
      adapter.respond(withTokens: true);
      await pending;
    });
    await tester.pumpAndSettle();
    expect(DataSp.userID, 'other-user');
    expect(DataSp.chatToken, 'other-chat');
    expect(im.logins, 0);
    expect(find.text('password form'), findsOneWidget);
  });
}
