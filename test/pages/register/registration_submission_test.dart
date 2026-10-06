import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/register/profile/registration_avatar_service.dart';
import 'package:openim/pages/register/rules/registration_field.dart';
import 'package:openim/pages/register/set_password/set_password_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  _IM(this.events);
  final List<String> events;
  int logins = 0;
  Completer<void>? pendingLogin;
  @override
  Rx<UserFullInfo> userInfo =
      UserFullInfo.fromJson({'userID': 'new-user', 'faceURL': ''}).obs;
  @override
  Future<void> login(String account, String token) async {
    logins++;
    events.add('sdk');
    OpenIM.iMManager.userID = account;
    userInfo.value = UserFullInfo.fromJson({'userID': account, 'faceURL': ''});
    await pendingLogin?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Avatars extends RegistrationAvatarService {
  _Avatars(this.events);
  final List<String> events;
  int picks = 0;
  int uploads = 0;
  String? uploadedFor;
  RegistrationAvatar? uploadedAvatar;
  bool Function()? uploadCurrent;
  Completer<RegistrationAvatar?>? selection;
  Completer<String?>? uploadResponse;
  @override
  Future<RegistrationAvatar?> pick() {
    picks++;
    selection = Completer<RegistrationAvatar?>();
    return selection!.future;
  }

  @override
  Future<String?> upload(
    RegistrationAvatar avatar, {
    required String userID,
    required bool Function() isCurrent,
  }) {
    uploads++;
    events.add('upload');
    uploadedFor = userID;
    uploadedAvatar = avatar;
    uploadCurrent = isCurrent;
    uploadResponse = Completer<String?>();
    return uploadResponse!.future;
  }
}

class _Profile extends SetPasswordLogic {
  _Profile({required super.avatarService, required this.events});
  final List<String> events;
  bool liveRegistration = false;
  int registrations = 0;
  int passwordLogins = 0;
  Map<String, Object?>? submitted;
  Map<String, Object?>? loggedIn;
  bool Function()? loginCurrent;
  Completer<LoginCertificate>? registration;
  Completer<LoginCertificate>? loginResponse;
  @override
  Future<LoginCertificate> registerAccount({
    required String nickname,
    required String password,
    required String areaCode,
    required String verificationCode,
    String? phoneNumber,
    String? email,
    String? invitationCode,
  }) {
    registrations++;
    events.add('register');
    submitted = {
      'nickname': nickname,
      'password': password,
      'areaCode': areaCode,
      'verificationCode': verificationCode,
      'phoneNumber': phoneNumber,
      'email': email,
      'invitationCode': invitationCode
    };
    if (liveRegistration) {
      return super.registerAccount(
          nickname: nickname,
          password: password,
          areaCode: areaCode,
          verificationCode: verificationCode,
          phoneNumber: phoneNumber,
          email: email,
          invitationCode: invitationCode);
    }
    registration = Completer<LoginCertificate>();
    return registration!.future;
  }

  @override
  Future<LoginCertificate> loginRegisteredAccount({
    required String password,
    required String areaCode,
    required bool Function() isCurrent,
    String? phoneNumber,
    String? email,
  }) {
    passwordLogins++;
    events.add('password-login');
    loggedIn = {
      'password': password,
      'areaCode': areaCode,
      'phoneNumber': phoneNumber,
      'email': email
    };
    loginCurrent = isCurrent;
    loginResponse = Completer<LoginCertificate>();
    return loginResponse!.future;
  }
}

class _HTTP implements HttpClientAdapter {
  int requests = 0;
  RequestOptions? lastRequest;
  Completer<ResponseBody>? response;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    requests++;
    lastRequest = options;
    response = Completer<ResponseBody>();
    return response!.future;
  }

  void respond({int code = 0}) => response!.complete(ResponseBody.fromString(
          jsonEncode({
            'errCode': code,
            'errMsg': code == 0 ? '' : 'NicknameAlreadyUsed',
            'data': {
              'userID': 'new-user',
              'chatToken': 'new-chat',
              'imToken': 'new-im'
            }
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          }));
}

LoginCertificate _certificate(
        {String chat = 'new-chat', String im = 'new-im'}) =>
    LoginCertificate.fromJson(
        {'userID': 'new-user', 'chatToken': chat, 'imToken': im});

RegistrationAvatar _avatar() => RegistrationAvatar(
    path: '/test/avatar.png',
    name: 'avatar.png',
    bytes: Uint8List.fromList([1, 2, 3]));

const _arguments = {
  'phoneNumber': '13800138000',
  'email': null,
  'areaCode': '+86',
  'usedFor': 1,
  'verificationCode': '123456',
  'invitationCode': 'INVITE123',
  'password': 'password1'
};

Widget _app() => MediaQuery(
    data: const MediaQueryData(size: Size(800, 600)),
    child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(initialEntries: [
          OverlayEntry(
              builder: (_) => GetMaterialApp(
                      locale: Get.locale,
                      translations: TranslationService(),
                      initialRoute: '/',
                      builder: EasyLoading.init(),
                      getPages: [
                        GetPage(
                            name: '/',
                            page: () =>
                                const Scaffold(body: Text('register form'))),
                        GetPage(
                            name: AppRoutes.setPassword,
                            page: () =>
                                const Scaffold(body: Text('profile form'))),
                        GetPage(
                            name: AppRoutes.login,
                            page: () =>
                                const Scaffold(body: Text('login form'))),
                        GetPage(
                            name: AppRoutes.home,
                            page: () =>
                                const Scaffold(body: Text('main ready'))),
                      ]))
        ])));

Future<void> _flushUntil(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

Future<void> _laterSession() async {
  OpenIM.iMManager.userID = 'later-user';
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': 'later-user',
    'chatToken': 'later-chat',
    'imToken': 'later-im'
  }));
}

Future<void> _stale(String reason) async {
  if (reason == 'closed') {
    await Get.delete<SetPasswordLogic>(force: true);
  } else if (reason == 'later-session') {
    await _laterSession();
  } else {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'new-user',
      'chatToken': 'new-chat',
      'imToken': 'rotated-im'
    }));
  }
}

Future<_Profile> _mount(
    WidgetTester tester, _Avatars avatars, List<String> events) async {
  await tester.pumpWidget(_app());
  Get.toNamed(AppRoutes.setPassword, arguments: _arguments);
  await tester.pumpAndSettle();
  final logic = Get.put<SetPasswordLogic>(
      _Profile(avatarService: avatars, events: events),
      permanent: true) as _Profile;
  logic.nicknameCtrl.text = '  Alice  ';
  return logic;
}

Future<void> _chooseAvatar(
    WidgetTester tester, _Profile logic, _Avatars avatars) async {
  await tester.runAsync(() async {
    final selection = logic.pickAvatar();
    avatars.selection!.complete(_avatar());
    await selection;
  });
}

Future<void> _settleToast(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _IM im;
  late _Avatars avatars;
  late _HTTP adapter;
  late List<String> events;
  setUp(() async {
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'none';
    events = [];
    im = Get.put<IMController>(_IM(events), permanent: true) as _IM;
    avatars = _Avatars(events);
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    http.dio = Dio();
    HttpUtil.init();
    adapter = _HTTP();
    http.dio.httpClientAdapter = adapter;
    configureEasyLoadingInteractions();
  });
  tearDown(() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    http.dio.close(force: true);
    Get.reset();
  });

  testWidgets('invalid profile nicknames never register an account',
      (tester) async {
    final logic = await _mount(tester, avatars, events);
    for (final nickname in ['', ' ', 'A']) {
      logic.nicknameCtrl.text = nickname;
      expect(logic.enabled.value, isFalse);
      await logic.nextStep();
      expect(logic.errorFor(RegistrationField.nickname), isNotNull);
    }
    expect(logic.registrations, 0);
    expect(im.logins, 0);
    expect(avatars.uploads, 0);
  });

  testWidgets(
      'single-flight profile submission retains its registered snapshot',
      (tester) async {
    final logic = await _mount(tester, avatars, events);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => logic.registrations == 1);
      await logic.nextStep();
      logic.nicknameCtrl.text = 'Bob';
      logic.pwdCtrl.text = 'changed1';
      logic.pwdAgainCtrl.text = 'changed1';
      logic.registration!.complete(_certificate(chat: '', im: ''));
      await _flushUntil(() => logic.passwordLogins == 1);
      await logic.nextStep();
      expect(logic.submitted, {
        'nickname': 'Alice',
        'password': 'password1',
        'areaCode': '+86',
        'verificationCode': '123456',
        'phoneNumber': '13800138000',
        'email': null,
        'invitationCode': 'INVITE123'
      });
      expect(logic.loggedIn!['password'], 'password1');
      logic.loginResponse!.complete(_certificate());
      await pending;
    });
    expect(logic.registrations, 1);
    expect(logic.passwordLogins, 1);
    expect(im.logins, 1);
  });

  testWidgets('registration logs into SDK then uploads and applies the avatar',
      (tester) async {
    final logic = await _mount(tester, avatars, events);
    await _chooseAvatar(tester, logic, avatars);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => logic.registrations == 1);
      logic.registration!.complete(_certificate());
      await _flushUntil(() => avatars.uploads == 1);
      expect(events, ['register', 'sdk', 'upload']);
      expect(avatars.uploadedFor, 'new-user');
      expect(avatars.uploadedAvatar, same(logic.avatar.value));
      expect(avatars.uploadCurrent!(), isTrue);
      expect(im.userInfo.value.faceURL, isEmpty);
      expect(Get.currentRoute, AppRoutes.setPassword);
      avatars.uploadResponse!.complete('https://media.example/avatar.png');
      await pending;
    });
    await tester.pumpAndSettle();
    expect(im.userInfo.value.faceURL, 'https://media.example/avatar.png');
    expect(DataSp.userID, 'new-user');
    expect(find.text('main ready'), findsOneWidget);
  });

  for (final missing in [
    (chat: '', im: ''),
    (chat: 'new-chat', im: ''),
    (chat: '', im: 'new-im')
  ]) {
    testWidgets(
        'missing signup tokens use registered password then avatar: $missing',
        (tester) async {
      final logic = await _mount(tester, avatars, events);
      await _chooseAvatar(tester, logic, avatars);
      await tester.runAsync(() async {
        final pending = logic.nextStep();
        await _flushUntil(() => logic.registrations == 1);
        logic.registration!
            .complete(_certificate(chat: missing.chat, im: missing.im));
        await _flushUntil(() => logic.passwordLogins == 1);
        expect(logic.loggedIn, {
          'password': 'password1',
          'areaCode': '+86',
          'phoneNumber': '13800138000',
          'email': null
        });
        expect(logic.loginCurrent!(), isTrue);
        logic.loginResponse!.complete(_certificate());
        await _flushUntil(() => avatars.uploads == 1);
        expect(events, ['register', 'password-login', 'sdk', 'upload']);
        avatars.uploadResponse!.complete('https://media.example/avatar.png');
        await pending;
      });
      await tester.pumpAndSettle();
      expect(logic.registrations, 1);
      expect(im.logins, 1);
      expect(find.text('main ready'), findsOneWidget);
    });
  }

  testWidgets('optional avatar can be skipped after successful registration',
      (tester) async {
    final logic = await _mount(tester, avatars, events);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => logic.registrations == 1);
      logic.registration!.complete(_certificate());
      await pending;
    });
    await tester.pumpAndSettle();
    expect(im.logins, 1);
    expect(avatars.uploads, 0);
    expect(find.text('main ready'), findsOneWidget);
  });

  testWidgets(
      'failed avatar upload retries on profile without registering or SDK login again',
      (tester) async {
    final logic = await _mount(tester, avatars, events);
    await _chooseAvatar(tester, logic, avatars);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => logic.registrations == 1);
      logic.registration!.complete(_certificate());
      await _flushUntil(() => avatars.uploads == 1);
      avatars.uploadResponse!.completeError(StateError('upload failed'));
      await pending;
    });
    await _settleToast(tester);
    expect(logic.accountCreated.value, isTrue);
    expect(logic.avatarUploadFailed.value, isTrue);
    expect(logic.submitting.value, isFalse);
    expect(find.text('profile form'), findsOneWidget);
    await EasyLoading.dismiss(animation: false);
    await tester.runAsync(() async {
      final retry = logic.nextStep();
      await _flushUntil(() => avatars.uploads == 2);
      expect(logic.registrations, 1);
      expect(logic.passwordLogins, 0);
      expect(im.logins, 1);
      avatars.uploadResponse!.complete('https://media.example/avatar.png');
      await retry;
    });
    await tester.pumpAndSettle();
    expect(im.userInfo.value.faceURL, 'https://media.example/avatar.png');
    expect(find.text('main ready'), findsOneWidget);
  });

  testWidgets(
      'password-login retry reuses the created account and first password',
      (tester) async {
    final logic = await _mount(tester, avatars, events);
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => logic.registrations == 1);
      logic.registration!.complete(_certificate(chat: '', im: ''));
      await _flushUntil(() => logic.passwordLogins == 1);
      logic.loginResponse!.completeError((1002, 'failed password login'));
      await pending;
    });
    await _settleToast(tester);
    await EasyLoading.dismiss(animation: false);
    logic.pwdCtrl.text = 'different1';
    logic.pwdAgainCtrl.text = 'different1';
    await tester.runAsync(() async {
      final retry = logic.nextStep();
      await _flushUntil(() => logic.passwordLogins == 2);
      expect(logic.registrations, 1);
      expect(logic.loggedIn!['password'], 'password1');
      logic.loginResponse!.complete(_certificate());
      await retry;
    });
    await tester.pumpAndSettle();
    expect(im.logins, 1);
    expect(find.text('main ready'), findsOneWidget);
  });

  testWidgets('canceling avatar picker does not select or upload an avatar',
      (tester) async {
    final logic = await _mount(tester, avatars, events);
    await tester.runAsync(() async {
      final selection = logic.pickAvatar();
      expect(logic.pickingAvatar.value, isTrue);
      avatars.selection!.complete(null);
      await selection;
    });
    expect(logic.avatar.value, isNull);
    expect(logic.pickingAvatar.value, isFalse);
    expect(logic.registrations, 0);
    expect(avatars.uploads, 0);
  });

  for (final stale in ['closed', 'later-session']) {
    testWidgets('late avatar selection is ignored after $stale',
        (tester) async {
      final logic = await _mount(tester, avatars, events);
      await tester.runAsync(() async {
        final selection = logic.pickAvatar();
        await _stale(stale);
        avatars.selection!.complete(_avatar());
        await selection;
      });
      expect(logic.avatar.value, isNull);
      expect(avatars.uploads, 0);
      expect(EasyLoading.isShow, isFalse);
    });
    for (final failed in [false, true]) {
      testWidgets(
          'late registration result is ignored after $stale, error=$failed',
          (tester) async {
        final logic = await _mount(tester, avatars, events);
        await _chooseAvatar(tester, logic, avatars);
        await tester.runAsync(() async {
          final pending = logic.nextStep();
          await _flushUntil(() => logic.registrations == 1);
          await _stale(stale);
          if (failed) {
            logic.registration!.completeError((20018, 'NicknameAlreadyUsed'));
          } else {
            logic.registration!.complete(_certificate());
          }
          await pending;
        });
        await tester.pumpAndSettle();
        expect(logic.passwordLogins, 0);
        expect(im.logins, 0);
        expect(avatars.uploads, 0);
        expect(DataSp.userID, stale == 'closed' ? isNull : 'later-user');
        expect(find.text('profile form'), findsOneWidget);
        expect(EasyLoading.isShow, isFalse);
      });
    }
    testWidgets('late registered-account login is ignored after $stale',
        (tester) async {
      final logic = await _mount(tester, avatars, events);
      await _chooseAvatar(tester, logic, avatars);
      await tester.runAsync(() async {
        final pending = logic.nextStep();
        await _flushUntil(() => logic.registrations == 1);
        logic.registration!.complete(_certificate(chat: '', im: ''));
        await _flushUntil(() => logic.passwordLogins == 1);
        await _stale(stale);
        expect(logic.loginCurrent!(), isFalse);
        logic.loginResponse!.complete(_certificate());
        await pending;
      });
      await tester.pumpAndSettle();
      expect(im.logins, 0);
      expect(avatars.uploads, 0);
      expect(find.text('profile form'), findsOneWidget);
      expect(EasyLoading.isShow, isFalse);
    });
  }

  for (final stale in ['closed', 'later-session', 'im-token-only']) {
    testWidgets('late SDK result cannot upload or navigate after $stale',
        (tester) async {
      final logic = await _mount(tester, avatars, events);
      await _chooseAvatar(tester, logic, avatars);
      await tester.runAsync(() async {
        im.pendingLogin = Completer<void>();
        final pending = logic.nextStep();
        await _flushUntil(() => logic.registrations == 1);
        logic.registration!.complete(_certificate());
        await _flushUntil(() => im.logins == 1);
        await _stale(stale);
        im.pendingLogin!.completeError(StateError('late SDK error'));
        await pending;
      });
      await tester.pumpAndSettle();
      expect(avatars.uploads, 0);
      expect(find.text('profile form'), findsOneWidget);
      expect(EasyLoading.isShow, isFalse);
    });
    testWidgets('late upload cannot apply avatar or navigate after $stale',
        (tester) async {
      final logic = await _mount(tester, avatars, events);
      await _chooseAvatar(tester, logic, avatars);
      await tester.runAsync(() async {
        final pending = logic.nextStep();
        await _flushUntil(() => logic.registrations == 1);
        logic.registration!.complete(_certificate());
        await _flushUntil(() => avatars.uploads == 1);
        await _stale(stale);
        expect(avatars.uploadCurrent!(), isFalse);
        avatars.uploadResponse!.complete('https://media.example/avatar.png');
        await pending;
      });
      await tester.pumpAndSettle();
      expect(im.userInfo.value.faceURL, isEmpty);
      expect(find.text('profile form'), findsOneWidget);
      expect(EasyLoading.isShow, isFalse);
    });
  }

  testWidgets(
      'profile registration sends trimmed nickname and hashes password once',
      (tester) async {
    final logic = await _mount(tester, avatars, events)
      ..liveRegistration = true;
    await tester.runAsync(() async {
      final pending = logic.nextStep();
      await _flushUntil(() => adapter.requests == 1);
      final payload = adapter.lastRequest!.data as Map;
      final user = payload['user'] as Map;
      expect(adapter.lastRequest!.path, Urls.register);
      expect(user['nickname'], 'Alice');
      expect(user['phoneNumber'], '13800138000');
      expect(user['password'], '7c6a180b36896a0a8c02787eeafb0e4c');
      expect(payload['verifyCode'], '123456');
      adapter.respond();
      await pending;
    });
    await tester.pumpAndSettle();
    expect(find.text('main ready'), findsOneWidget);
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
        'profile HTTP 200 nickname error shows one centered toast in $language',
        (tester) async {
      Get.locale = Locale(language);
      final logic = await _mount(tester, avatars, events)
        ..liveRegistration = true;
      var shown = 0;
      void onStatus(EasyLoadingStatus status) {
        if (status == EasyLoadingStatus.show) shown++;
      }

      EasyLoading.addStatusCallback(onStatus);
      addTearDown(() => EasyLoading.removeCallback(onStatus));
      await tester.runAsync(() async {
        final pending = logic.nextStep();
        await _flushUntil(() => adapter.requests == 1);
        adapter.respond(code: 20018);
        await pending;
      });
      await _settleToast(tester);
      final message = HttpUtil.errorMessage((20018, ''), path: Urls.register);
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('NicknameAlreadyUsed'), findsNothing);
      expect(logic.errorFor(RegistrationField.nickname), isNull);
      expect(logic.submitting.value, isFalse);
      expect(logic.nicknameCtrl.text, '  Alice  ');
      expect(shown, 1);
      expect(adapter.requests, 1);
      expect(logic.passwordLogins, 0);
      expect(im.logins, 0);
      expect(avatars.uploads, 0);
      final pageCenter =
          tester.getCenter(find.widgetWithText(Scaffold, 'profile form'));
      final toastCenter = tester.getCenter(find.text(message));
      expect(toastCenter.dx, closeTo(pageCenter.dx, 1));
      expect(toastCenter.dy, closeTo(pageCenter.dy, 1));
      await EasyLoading.dismiss(animation: false);
    });
  }
}
