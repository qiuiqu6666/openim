import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/session/local_session_exit.dart';
import 'package:openim/core/session/sdk_session_queue.dart';
import 'package:openim/services/account_privilege/account_privilege_runtime.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  bool get isRunningBackground => false;

  @override
  void clearMessageNotificationSession() {}

  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {}

  @override
  void markDeviceSyncUserActivity() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ForegroundApp extends AppController {
  int sessionReadyCalls = 0;
  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {
    sessionReadyCalls++;
  }
}

class _ForegroundIM extends IMController {
  // Exercise real login/foreground refresh without initializing native signaling
  // and alert services; the superclass hook initializes those services.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Profiles implements HttpClientAdapter {
  final replies = <Completer<ResponseBody>>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    final reply = Completer<ResponseBody>();
    replies.add(reply);
    return reply.future;
  }

  void complete(int index, String account, String nickname,
      {String? publicAccount, Object? isPrivileged}) {
    replies[index].complete(ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'data': {
            'users': [
              {
                'userID': account,
                'nickname': nickname,
                if (publicAccount != null) 'account': publicAccount,
                if (isPrivileged != null) 'isPrivileged': isPrivileged,
              }
            ]
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
  }

  void error(int index, int code) {
    replies[index].complete(ResponseBody.fromString(
        jsonEncode({
          'errCode': code,
          'errMsg': 'expired',
          'data': null,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _credentials(String account) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': account,
    'chatToken': '$account-chat',
    'imToken': '$account-im',
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _Profiles profiles;
  late List<String> nativeCalls;
  late String nativeAccount;
  late bool nativeLogged;
  Future<void> Function()? cleanup;
  String? rejectedLoginCode;
  setUp(() async {
    Get.testMode = true;
    Get.put<AppController>(_App());
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    AccountPrivilegeRuntime.store.reset();
    OpenIM.iMManager.userID = 'none';
    OpenIM.iMManager.isLogined = false;
    OpenIM.iMManager.token = null;
    http.dio = Dio();
    HttpUtil.init();
    profiles = _Profiles();
    http.dio.httpClientAdapter = profiles;
    nativeCalls = [];
    nativeAccount = 'none';
    nativeLogged = false;
    cleanup = null;
    rejectedLoginCode = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      switch (call.method) {
        case 'getLoginStatus':
          return nativeLogged ? LoginStatus.logged : LoginStatus.logout;
        case 'login':
          nativeAccount = (call.arguments as Map)['userID'] as String;
          nativeLogged = true;
          nativeCalls.add('login:$nativeAccount');
          if (rejectedLoginCode != null) {
            throw PlatformException(code: rejectedLoginCode!);
          }
          return null;
        case 'getSelfUserInfo':
          return jsonEncode(UserInfo(userID: nativeAccount).toJson());
        case 'logout':
          nativeCalls.add('logout:$nativeAccount');
          await cleanup?.call();
          nativeLogged = false;
          return null;
        default:
          throw StateError(call.method);
      }
    });
  });
  tearDown(() {
    AccountPrivilegeRuntime.store.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    http.dio.close(force: true);
    Get.reset();
  });

  test('a profile refresh before login does not read late userInfo', () async {
    final logic = IMController();
    expect(await logic.refreshMyFullInfo(), isFalse);
    expect(profiles.replies, isEmpty);
    logic.onClose();
  });

  testWidgets('login and entry refresh share one verified privilege read',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      expect(logic.userInfo.value.isPrivileged, isFalse);
      final foreground = logic.refreshMyFullInfo();
      final entry = AccountPrivilegeRuntime.store.refresh();
      await _flush();
      expect(profiles.replies, hasLength(1));
      profiles.complete(0, 'first', 'First', isPrivileged: true);
      expect(await foreground, isTrue);
      expect(await entry, isTrue);
      expect(logic.userInfo.value.isPrivileged, isTrue);
      expect(
          AccountPrivilegeRuntime.store
              .allows(userID: 'first', baseUrl: Config.appAuthUrl),
          isTrue);
      await logic.logout();
      expect(logic.userInfo.value.isPrivileged, isFalse);
      expect(
          AccountPrivilegeRuntime.store
              .allows(userID: 'first', baseUrl: Config.appAuthUrl),
          isFalse);
      logic.onClose();
    });
  });

  testWidgets('foreground refresh is safe before login and never blocks resume',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = Get.put<IMController>(_ForegroundIM());
      final app = _ForegroundApp();
      await app.runningBackground(false);
      expect(profiles.replies, isEmpty);
      expect(app.sessionReadyCalls, 1);
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      await app.runningBackground(false);
      await _flush();
      expect(app.sessionReadyCalls, 2);
      expect(profiles.replies, hasLength(1));
      profiles.complete(0, 'first', 'First', isPrivileged: true);
      await _flush();
      expect(logic.userInfo.value.isPrivileged, isTrue);
    });
  });

  testWidgets('direct entry refresh synchronizes model grant and revocation',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      profiles.complete(0, 'first', 'First');
      await _flush();
      final grant = AccountPrivilegeRuntime.store.refresh();
      await _flush();
      profiles.complete(1, 'first', 'First', isPrivileged: true);
      expect(await grant, isTrue);
      expect(logic.userInfo.value.isPrivileged, isTrue);
      final revoke = AccountPrivilegeRuntime.store.refresh();
      await _flush();
      profiles.complete(2, 'first', 'First', isPrivileged: false);
      expect(await revoke, isFalse);
      expect(logic.userInfo.value.isPrivileged, isFalse);
      logic.onClose();
    });
  });

  testWidgets('entry authentication failure clears a verified model privilege',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      final kicks = <dynamic>[];
      final subscription = Apis.kickoffController.stream.listen(kicks.add);
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      profiles.complete(0, 'first', 'First', isPrivileged: true);
      await _flush();
      expect(logic.userInfo.value.isPrivileged, isTrue);
      final entry = AccountPrivilegeRuntime.store.refresh();
      await _flush();
      profiles.error(1, 1503);
      expect(await entry, isFalse);
      await _flush();
      expect(logic.userInfo.value.isPrivileged, isFalse);
      expect(kicks, [1503]);
      await subscription.cancel();
      logic.onClose();
    });
  });

  testWidgets('a changed backend cannot grant privilege from a late profile',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      await DataSp.putServerConfig({'authUrl': 'https://changed.example/chat'});
      profiles.complete(0, 'first', 'Old backend', isPrivileged: true);
      await _flush();
      expect(logic.userInfo.value.isPrivileged, isFalse);
      expect(logic.userInfo.value.nickname, isNull);
      final refresh = logic.refreshMyFullInfo();
      await _flush();
      profiles.complete(1, 'first', 'New backend', isPrivileged: true);
      expect(await refresh, isTrue);
      expect(logic.userInfo.value.nickname, 'New backend');
      expect(logic.userInfo.value.isPrivileged, isTrue);
      logic.onClose();
    });
  });

  testWidgets('backend account is hydrated without replacing SDK identity',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('im_internal');
      await logic.login('im_internal', 'im_internal-im');
      await _flush();
      expect(logic.userInfo.value.account, isNull);
      profiles.complete(0, 'im_internal', 'Profile', publicAccount: '990001');
      await _flush();
      expect(logic.userInfo.value.account, '990001');
      expect(logic.userInfo.value.userID, 'im_internal');
      expect(OpenIM.iMManager.userID, 'im_internal');
      expect(DataSp.userID, 'im_internal');
      logic.onClose();
    });
  });

  testWidgets('an old profile cannot write into a later account profile',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      await logic.logout();
      await _credentials('second');
      await logic.login('second', 'second-im');
      await _flush();
      profiles.complete(1, 'second', 'Second profile',
          publicAccount: 'second99');
      await _flush();
      expect(logic.userInfo.value.account, 'second99');
      profiles.complete(0, 'first', 'First profile',
          publicAccount: 'first99', isPrivileged: true);
      await _flush();
      expect(logic.userInfo.value.userID, 'second');
      expect(logic.userInfo.value.nickname, 'Second profile');
      expect(logic.userInfo.value.account, 'second99');
      expect(logic.userInfo.value.isPrivileged, isFalse);
      logic.onClose();
    });
  });

  testWidgets('a profile request cannot update a closed controller',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      logic.onClose();
      profiles.complete(0, 'first', 'Late profile',
          publicAccount: 'late99', isPrivileged: true);
      await _flush();
      expect(logic.userInfo.value.nickname, isNull);
      expect(logic.userInfo.value.account, isNull);
      expect(logic.userInfo.value.isPrivileged, isFalse);
    });
  });

  testWidgets(
      'old profile authentication errors cannot clear or kick the current account',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      final kicks = <dynamic>[];
      final subscription = Apis.kickoffController.stream.listen(kicks.add);
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      await logic.logout();
      await _credentials('second');
      await logic.login('second', 'second-im');
      await _flush();
      profiles.complete(1, 'second', 'Second');
      profiles.error(0, 1503);
      await _flush();
      expect(kicks, isEmpty);
      expect(DataSp.userID, 'second');
      expect(logic.userInfo.value.nickname, 'Second');
      await subscription.cancel();
      logic.onClose();
    });
  });

  for (final code in [1502, 1503, 1506, 1507, 20101]) {
    testWidgets(
        'current profile auth error $code emits one normal session expiry event',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
      await tester.runAsync(() async {
        final logic = IMController();
        final kicks = <dynamic>[];
        final subscription = Apis.kickoffController.stream.listen(kicks.add);
        await _credentials('first');
        await logic.login('first', 'first-im');
        await _flush();
        profiles.error(0, code);
        await _flush();
        expect(kicks, [code]);
        await subscription.cancel();
        logic.onClose();
      });
    });
  }

  testWidgets(
      'local exit completes while the next native login waits for old cleanup',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      profiles.complete(0, 'first', 'First');
      await _flush();
      final cleanupReply = Completer<void>();
      cleanup = () => cleanupReply.future;
      var navigated = false;
      await exitLocalSession(
          logoutSdk: logic.logout,
          clearLocal: () async {
            await DataSp.removeLoginCertificate();
          },
          navigate: () => navigated = true,
          onCleanupError: (_, __) {});
      expect(navigated, isTrue);
      expect(DataSp.userID, isNull);
      await _credentials('second');
      final login = logic.login('second', 'second-im');
      await _flush();
      expect(nativeCalls, ['login:first', 'logout:first']);
      cleanupReply.complete();
      await login;
      await _flush();
      expect(nativeCalls, ['login:first', 'logout:first', 'login:second']);
      profiles.complete(1, 'second', 'Second');
      await _flush();
      expect(logic.userInfo.value.userID, 'second');
      logic.onClose();
    });
  });

  testWidgets(
      'failed cleanup cannot cause the SDK to reuse the old account for a new login',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      profiles.complete(0, 'first', 'First');
      await _flush();
      cleanup = () async => throw PlatformException(code: 'cleanup_failed');
      final errors = <Object>[];
      await exitLocalSession(
          logoutSdk: logic.logout,
          clearLocal: () async {
            await DataSp.removeLoginCertificate();
          },
          navigate: () {},
          onCleanupError: (error, _) => errors.add(error));
      await _credentials('second');
      await expectLater(logic.login('second', 'second-im'),
          throwsA(isA<PlatformException>()));
      await _flush();
      expect(nativeCalls, ['login:first', 'logout:first', 'logout:first']);
      expect(nativeLogged, isTrue);
      expect(nativeAccount, 'first');
      expect(logic.userInfo.value.userID, 'first');
      expect(errors.single, isA<PlatformException>());
      logic.onClose();
    });
  });

  testWidgets(
      'duplicate-login error returns before hung cleanup and its late cleanup cannot erase the next credentials',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic = IMController();
      final cleanupReply = Completer<void>();
      cleanup = () => cleanupReply.future;
      rejectedLoginCode = '13002';
      await _credentials('first');
      await expectLater(
          logic.login('first', 'first-im'), throwsA(isA<PlatformException>()));
      await _flush();
      expect(DataSp.userID, isNull);
      expect(cleanupReply.isCompleted, isFalse);
      expect(nativeCalls, ['login:first', 'logout:first']);
      rejectedLoginCode = null;
      await _credentials('second');
      final next = logic.login('second', 'second-im');
      await _flush();
      expect(nativeCalls, ['login:first', 'logout:first']);
      expect(DataSp.userID, 'second');
      cleanupReply.complete();
      await next;
      await _flush();
      expect(DataSp.userID, 'second');
      expect(nativeCalls, ['login:first', 'logout:first', 'login:second']);
      profiles.complete(0, 'second', 'Second');
      await _flush();
      logic.onClose();
    });
  });

  testWidgets(
      'retrying failed native cleanup has a deadline and a late reply cannot execute the expired login',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      final logic =
          IMController(loginStartTimeout: const Duration(milliseconds: 20));
      await _credentials('first');
      await logic.login('first', 'first-im');
      await _flush();
      profiles.complete(0, 'first', 'First');
      await _flush();
      cleanup = () async => throw PlatformException(code: 'cleanup_failed');
      await expectLater(logic.logout(), throwsA(isA<PlatformException>()));
      final retry = Completer<void>();
      cleanup = () => retry.future;
      await _credentials('second');
      await expectLater(
          logic.login('second', 'second-im'), throwsA(isA<SdkSessionBusy>()));
      expect(nativeCalls, ['login:first', 'logout:first', 'logout:first']);
      expect(nativeAccount, 'first');
      expect(DataSp.userID, 'second');
      retry.complete();
      await _flush();
      expect(nativeCalls, ['login:first', 'logout:first', 'logout:first']);
      expect(profiles.replies, hasLength(1));
      await logic.login('second', 'second-im');
      await _flush();
      expect(nativeCalls.last, 'login:second');
      profiles.complete(1, 'second', 'Second');
      await _flush();
      logic.onClose();
    });
  });
}
