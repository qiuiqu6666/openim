import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/services/auth_credentials/auth_credentials_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  int logins = 0;
  Completer<void>? response;
  @override
  Future<void> login(String account, String token) async {
    logins++;
    OpenIM.iMManager.userID = account;
    await response?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache extends GetxController implements CacheController {
  int resets = 0;
  @override
  void resetCache() => resets++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Login extends LoginLogic {
  _Login({super.credentialsStore});
  @override
  void getPackageInfo() {}
}

class _PendingCredentials extends AuthCredentialsStore {
  final response = Completer<StoredAuthCredentials>();
  @override
  Future<StoredAuthCredentials> load() => response.future;
}

class _PendingSave extends AuthCredentialsStore {
  int saves = 0;
  final response = Completer<bool>();
  @override
  Future<bool> saveSuccessful({
    required String account,
    required String areaCode,
    required int loginType,
    required String? password,
    required bool rememberPassword,
    required bool Function() isCurrent,
  }) {
    saves++;
    return response.future;
  }
}

class _UnavailableStore extends AuthCredentialsStore {
  @override
  Future<bool> saveSuccessful({
    required String account,
    required String areaCode,
    required int loginType,
    required String? password,
    required bool rememberPassword,
    required bool Function() isCurrent,
  }) async =>
      throw PlatformException(code: 'storage-unavailable');
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

  void success() => _response!.complete(ResponseBody.fromString(
          jsonEncode({
            'errCode': 0,
            'data': {
              'userID': 'self',
              'chatToken': 'self-chat',
              'imToken': 'self-im'
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          }));
  void failRequest() => _response!.completeError(DioException(
      requestOptions: RequestOptions(path: 'login'),
      type: DioExceptionType.connectionError));
  void businessError() => _response!.complete(ResponseBody.fromString(
        jsonEncode({'errCode': 1002, 'errMsg': 'backend English failure'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      ));
}

Widget _app() => MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(initialEntries: [
          OverlayEntry(
              builder: (_) => GetMaterialApp(initialRoute: '/', getPages: [
                    GetPage(
                        name: '/',
                        page: () => const Scaffold(body: Text('sign in'))),
                    GetPage(
                        name: AppRoutes.home,
                        page: () => const Scaffold(body: Text('main ready'))),
                  ]))
        ]),
      ),
    );
Future<void> _flushUntil(bool Function() ready) async {
  for (var i = 0; i < 50 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

// Secure-storage futures and their serialized queues run outside the widget
// clock. Construct the store there as well, so its initial queue is not paused.
Future<_Login> _initLogin(WidgetTester tester,
        {AuthCredentialsStore Function()? createStore}) async =>
    (await tester.runAsync(() async {
      final logic = _Login(credentialsStore: createStore?.call())..onInit();
      await Future<void>.value();
      return logic;
    }))!;

Future<StoredAuthCredentials> _loadCredentials(WidgetTester tester) async =>
    (await tester.runAsync(() => AuthCredentialsStore().load()))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _HTTP adapter;
  late _IM im;
  late _Cache cache;
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'none';
    im = Get.put<IMController>(_IM(), permanent: true) as _IM;
    cache = Get.put<CacheController>(_Cache(), permanent: true) as _Cache;
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
  });
  tearDown(() {
    LoadingView.singleton.dismiss();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    http.dio.close(force: true);
    Get.reset();
  });

  testWidgets(
      'manual login is single-flight and navigates without a conversation-list prerequisite',
      (tester) async {
    var listRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      listRequests++;
      return Completer<String>().future;
    });
    await tester.pumpWidget(_app());
    final logic = await _initLogin(tester);
    logic.loginType.value = LoginType.account;
    logic.phoneCtrl.text = 'account';
    logic.pwdCtrl.text = 'password';
    await tester.runAsync(() async {
      final login = logic.login();
      await _flushUntil(() => adapter.requests == 1);
      await logic.login();
      expect(adapter.requests, 1);
      adapter.success();
      await login;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(im.logins, 1);
    expect(cache.resets, 1);
    expect(listRequests, 0);
    expect(find.text('main ready'), findsOneWidget);
    final remembered = await _loadCredentials(tester);
    expect(remembered.account, 'account');
    expect(remembered.password, 'password');
    expect(DataSp.getLoginAccount(), isNot(contains('password')));
    logic.onClose();
  });

  testWidgets(
      'a closed login page ignores a late successful authentication response',
      (tester) async {
    await tester.pumpWidget(_app());
    final logic = await _initLogin(tester);
    logic.loginType.value = LoginType.account;
    logic.phoneCtrl.text = 'account';
    logic.pwdCtrl.text = 'password';
    await tester.runAsync(() async {
      final login = logic.login();
      await _flushUntil(() => adapter.requests == 1);
      logic.onClose();
      adapter.success();
      await login;
    });
    await tester.pump();
    expect(im.logins, 0);
    expect(cache.resets, 0);
    expect(DataSp.userID, isNull);
    expect(find.text('sign in'), findsOneWidget);
    expect((await _loadCredentials(tester)).account, isEmpty);
  });

  testWidgets('late credential restore preserves typing and remember choice',
      (tester) async {
    late _PendingCredentials store;
    final logic = await _initLogin(tester,
        createStore: () => store = _PendingCredentials());
    logic.phoneCtrl.text = 'typed-account';
    logic.pwdCtrl.text = 'typed-password';
    await tester.runAsync(() async {
      await logic.toggleRememberPassword(false);
      store.response.complete(const StoredAuthCredentials(
          account: 'saved-account', password: 'saved-password'));
      await Future<void>.value();
    });
    await tester.pump();
    expect(logic.phoneCtrl.text, 'typed-account');
    expect(logic.pwdCtrl.text, 'typed-password');
    expect(logic.rememberPassword.value, isFalse);
    logic.onClose();
  });

  testWidgets(
      'selection and composing notifications do not cancel remembered password restore',
      (tester) async {
    await tester.runAsync(() async {
      await DataSp.putLoginAccount({
        'phoneNumber': '13800138000',
        'areaCode': '+86',
        'loginType': LoginType.phone.rawValue,
      });
    });
    late _PendingCredentials store;
    final logic = await _initLogin(tester,
        createStore: () => store = _PendingCredentials());
    expect(logic.phoneCtrl.text, '13800138000');
    expect(logic.pwdCtrl.text, isEmpty);

    // A mounted TextField can report selection/composing changes without the
    // user changing either text. Slow native storage must still fill the form.
    logic.phoneCtrl.value = logic.phoneCtrl.value.copyWith(
      selection: const TextSelection.collapsed(offset: 11),
      composing: const TextRange(start: 0, end: 1),
    );
    logic.pwdCtrl.value = logic.pwdCtrl.value.copyWith(
      selection: const TextSelection.collapsed(offset: 0),
      composing: const TextRange(start: 0, end: 0),
    );
    await tester.runAsync(() async {
      store.response.complete(const StoredAuthCredentials(
        account: '13800138000',
        password: 'remembered-password',
      ));
      await Future<void>.value();
    });
    await tester.pump();
    expect(logic.phoneCtrl.text, '13800138000');
    expect(logic.pwdCtrl.text, 'remembered-password');
    expect(logic.rememberPassword.value, isTrue);
    expect(logic.enabled.value, isTrue);
    logic.onClose();
  });

  for (final remember in [true, false]) {
    testWidgets(
        'successful login then local logout restores account and respects remember=$remember',
        (tester) async {
      await tester.pumpWidget(_app());
      final first = await _initLogin(tester);
      first.phoneCtrl.text = '13800138000';
      first.pwdCtrl.text = 'remembered-password';
      await tester.runAsync(() async {
        await first.toggleRememberPassword(remember);
        final login = first.login();
        await _flushUntil(() => adapter.requests == 1);
        adapter.success();
        await login;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(im.logins, 1);
      expect(find.text('main ready'), findsOneWidget);
      expect(DataSp.userID, 'self');
      first.onClose();

      // Local logout clears session tokens, while the remembered-login store
      // survives both the old controller and the new login-page lifetime.
      await tester.runAsync(() async {
        await DataSp.removeLoginCertificate();
      });
      OpenIM.iMManager.userID = '';
      expect(DataSp.userID, isNull);
      expect(DataSp.chatToken, isNull);
      expect(DataSp.imToken, isNull);
      final returned = await _initLogin(tester);
      await tester.runAsync(() => _flushUntil(() => remember
          ? returned.pwdCtrl.text == 'remembered-password'
          : returned.rememberPassword.value == false));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            TextField(
                key: const ValueKey('returned-login-account'),
                controller: returned.phoneCtrl),
            TextField(
                key: const ValueKey('returned-login-password'),
                controller: returned.pwdCtrl,
                obscureText: true),
          ]),
        ),
      ));
      expect(returned.phoneCtrl.text, '13800138000');
      expect(returned.loginType.value, LoginType.phone);
      expect(returned.pwdCtrl.text, remember ? 'remembered-password' : isEmpty);
      expect(returned.rememberPassword.value, remember);
      expect(returned.enabled.value, remember);
      final passwordField = tester.widget<TextField>(
          find.byKey(const ValueKey('returned-login-password')));
      expect(passwordField.controller!.text,
          remember ? 'remembered-password' : isEmpty);
      expect(passwordField.obscureText, isTrue);
      final stored = await _loadCredentials(tester);
      expect(stored.account, '13800138000');
      expect(stored.password, remember ? 'remembered-password' : isNull);
      expect(stored.rememberPassword, remember);
      await tester.pumpWidget(const SizedBox.shrink());
      returned.onClose();
    });
  }

  testWidgets('untouched form restores safely and closed page ignores restore',
      (tester) async {
    late _PendingCredentials store;
    final logic = await _initLogin(tester,
        createStore: () => store = _PendingCredentials());
    await tester.runAsync(() async {
      store.response.complete(const StoredAuthCredentials(
          account: '13800138000', password: 'remembered-password'));
      await Future<void>.value();
    });
    await tester.pump();
    expect(logic.phoneCtrl.text, '13800138000');
    expect(logic.pwdCtrl.text, 'remembered-password');
    expect(logic.loginType.value, LoginType.phone);
    expect(logic.enabled.value, isTrue);
    logic.onClose();
    late _PendingCredentials closedStore;
    final closed = await _initLogin(tester,
        createStore: () => closedStore = _PendingCredentials());
    closed.onClose();
    await tester.runAsync(() async {
      closedStore.response.complete(const StoredAuthCredentials(
          account: 'late-account', password: 'late-password'));
      await Future<void>.value();
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('password is saved only after SDK accepts the login',
      (tester) async {
    await tester.pumpWidget(_app());
    late _PendingSave store;
    final logic =
        await _initLogin(tester, createStore: () => store = _PendingSave());
    logic.phoneCtrl.text = 'account';
    logic.pwdCtrl.text = 'password';
    await tester.runAsync(() async {
      im.response = Completer<void>();
      final login = logic.login();
      await _flushUntil(() => adapter.requests == 1);
      adapter.success();
      await _flushUntil(() => im.logins == 1);
      expect(store.saves, 0);
      im.response!.complete();
      await _flushUntil(() => store.saves == 1);
      expect(cache.resets, 0);
      logic.onClose();
      store.response.complete(false);
      await login;
    });
    expect(cache.resets, 0);
    expect(find.text('sign in'), findsOneWidget);
  });

  testWidgets('secure storage failure still permits authenticated navigation',
      (tester) async {
    await tester.pumpWidget(_app());
    final logic = await _initLogin(tester, createStore: _UnavailableStore.new);
    logic.phoneCtrl.text = 'account';
    logic.pwdCtrl.text = 'password';
    await tester.runAsync(() async {
      final login = logic.login();
      await _flushUntil(() => adapter.requests == 1);
      adapter.success();
      await login;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(im.logins, 1);
    expect(cache.resets, 1);
    expect(find.text('main ready'), findsOneWidget);
    logic.onClose();
  });

  testWidgets(
      'HTTP 200 business failure maps to one current-language form error',
      (tester) async {
    await tester.pumpWidget(_app());
    final logic = await _initLogin(tester);
    logic.phoneCtrl.text = 'account';
    logic.pwdCtrl.text = 'password';
    Get.locale = const Locale('zh', 'CN');
    await tester.runAsync(() async {
      final login = logic.login();
      await _flushUntil(() => adapter.requests == 1);
      Get.locale = const Locale('en', 'US');
      adapter.businessError();
      await login;
    });
    expect(
        logic.formError,
        HttpUtil.errorMessage((1002, 'backend English failure'),
            path: Urls.login));
    expect(logic.formError, isNot(contains('backend English failure')));
    expect(logic.accountError, isNull);
    expect(logic.passwordError, isNull);
    expect(im.logins, 0);
    expect(logic.submitting.value, isFalse);
    final englishError = logic.formError;
    Get.locale = const Locale('zh', 'CN');
    expect(logic.formError, isNot(englishError));
    expect(
        logic.formError,
        HttpUtil.errorMessage((1002, 'backend English failure'),
            path: Urls.login));
    logic.pwdCtrl.text = 'corrected-password';
    expect(logic.formError, isNull);
    logic.onClose();
  });

  testWidgets('an edited form ignores an older failed login response',
      (tester) async {
    await tester.pumpWidget(_app());
    final logic = await _initLogin(tester);
    logic.phoneCtrl.text = 'account';
    logic.pwdCtrl.text = 'password';
    await tester.runAsync(() async {
      final login = logic.login();
      await _flushUntil(() => adapter.requests == 1);
      logic.phoneCtrl.text = 'edited-account';
      adapter.businessError();
      await login;
    });
    expect(logic.formError, isNull);
    expect(im.logins, 0);
    logic.onClose();
  });

  for (final target in [
    (value: '13800138000', identity: '13800138000', key: 'phoneNumber'),
    (value: 'user@example.com', identity: 'user@example.com', key: 'email'),
    (value: '12345', identity: '12345', key: 'account'),
    (value: 'username', identity: 'username', key: 'account'),
    (value: ' @username ', identity: 'username', key: 'account'),
    (value: '@ username', identity: 'username', key: 'account'),
    (value: '@@123456', identity: '123456', key: 'account'),
    (value: '@13800138000', identity: '13800138000', key: 'account'),
  ]) {
    testWidgets('password login dispatches ${target.key} for ${target.value}',
        (tester) async {
      await tester.pumpWidget(_app());
      final logic = await _initLogin(tester);
      logic.phoneCtrl.text = target.value;
      logic.pwdCtrl.text = 'password';
      await tester.runAsync(() async {
        final login = logic.login();
        await _flushUntil(() => adapter.requests == 1);
        final payload = adapter.lastRequest!.data as Map;
        expect(payload[target.key], target.identity);
        for (final key in ['phoneNumber', 'email', 'account']) {
          if (key != target.key) expect(payload[key], isNull);
        }
        expect(payload['areaCode'], '+86');
        adapter.success();
        await login;
        expect(logic.phoneCtrl.text, target.value);
        expect((await AuthCredentialsStore().load()).account, target.identity);
      });
      logic.onClose();
    });
  }

  for (final closed in [false, true]) {
    testWidgets(
        'an old authentication failure cannot clear later credentials when pageClosed=$closed',
        (tester) async {
      await tester.pumpWidget(_app());
      final logic = await _initLogin(tester);
      logic.loginType.value = LoginType.account;
      logic.phoneCtrl.text = 'account';
      logic.pwdCtrl.text = 'password';
      await tester.runAsync(() async {
        final login = logic.login();
        await _flushUntil(() => adapter.requests == 1);
        if (closed) logic.onClose();
        OpenIM.iMManager.userID = 'later';
        await DataSp.putLoginCertificate(LoginCertificate.fromJson({
          'userID': 'later',
          'chatToken': 'later-chat',
          'imToken': 'later-im',
        }));
        adapter.failRequest();
        await login;
      });
      await tester.pump();
      expect(im.logins, 0);
      expect(DataSp.userID, 'later');
      expect(logic.formError, isNull);
      expect(Get.currentRoute, '/');
      expect(find.text('sign in'), findsOneWidget);
      if (!closed) logic.onClose();
    });
  }
}
