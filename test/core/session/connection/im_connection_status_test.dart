import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  void beginBadgeSession(String accountID, String token) {}

  @override
  void clearBadgeSession() {}

  @override
  void clearMessageNotificationSession() {}

  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends IMController {
  // Keep the real session queue and SDK login wrapper, without profile HTTP.
  @override
  Future<bool> refreshMyFullInfo() async => false;
}

Future<void> _credentials(String account, {String? token}) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': account,
    'chatToken': '$account-chat',
    'imToken': token ?? '$account-im',
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null);
  const channel = MethodChannel('flutter_openim_sdk');
  late _IM logic;
  late String nativeAccount;
  late bool nativeLogged;
  int? nativeStatusOverride;
  Future<void> Function()? cleanup;
  late List<String> nativeCalls;
  late List<StreamSubscription<dynamic>> subscriptions;

  setUp(() async {
    Get.testMode = true;
    Get.put<AppController>(_App());
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = '';
    OpenIM.iMManager.token = null;
    OpenIM.iMManager.isLogined = false;
    nativeAccount = '';
    nativeLogged = false;
    nativeStatusOverride = null;
    cleanup = null;
    nativeCalls = [];
    subscriptions = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getLoginStatus':
          return nativeStatusOverride ??
              (nativeLogged ? LoginStatus.logged : LoginStatus.logout);
        case 'login':
          nativeAccount = (call.arguments as Map)['userID'] as String;
          nativeLogged = true;
          nativeCalls.add('login:$nativeAccount');
          return null;
        case 'getSelfUserInfo':
          return jsonEncode(UserInfo(userID: nativeAccount).toJson());
        case 'logout':
          nativeCalls.add('logout:$nativeAccount');
          await cleanup?.call();
          nativeLogged = false;
          nativeStatusOverride = null;
          return null;
        case 'setAppBackgroundStatus':
        case 'networkStatusChanged':
          nativeCalls.add(call.method);
          return null;
        default:
          throw StateError(call.method);
      }
    });
    logic = _IM();
    await _credentials('first');
    await logic.login('first', 'first-im');
  });

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    logic.onClose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    Get.reset();
  });

  testWidgets('foreground reconnect rechecks sync without waiting for a send',
      (tester) async {
    // Own the status subscription and its timers in the widget test clock.
    logic.onClose();
    logic = _IM();
    await logic.login('first', 'first-im');
    logic.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.pump(const Duration(seconds: 3));
    nativeCalls.clear();
    logic.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(nativeCalls, isEmpty,
        reason: 'A healthy sync finish must not start another metadata sync.');
    nativeCalls.clear();
    // The OS still reports the same network and the app never backgrounds.
    logic.imSdkStatus(IMSdkStatus.connecting);
    logic.imSdkStatus(IMSdkStatus.connectionSucceeded);
    logic.imSdkStatus(IMSdkStatus.syncStart);
    logic.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    logic.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(nativeCalls, ['setAppBackgroundStatus']);
    expect(logic.currentSdkStatus, IMSdkStatus.syncEnded);
    // No forced socket close, re-login or recurring fast checks on success.
    await tester.pump(const Duration(seconds: 3));
    expect(nativeCalls, ['setAppBackgroundStatus']);
    logic.onClose();
  });

  Future<void> restartDartSession() async {
    logic.onClose();
    await Future<void>.delayed(Duration.zero);
    // Hot restart drops Dart state, not the process-owned native session.
    OpenIM.iMManager.userID = '';
    OpenIM.iMManager.token = null;
    OpenIM.iMManager.isLogined = false;
    logic = _IM();
  }

  testWidgets('sync failures back off without closing transport',
      (tester) async {
    logic.onClose();
    logic = _IM();
    await logic.login('first', 'first-im');
    logic.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    nativeCalls.clear();
    const delays = [3, 3, 6, 12];
    for (var i = 0; i < delays.length; i++) {
      logic.imSdkStatus(IMSdkStatus.syncStart);
      logic.imSdkStatus(IMSdkStatus.syncFailed);
      await tester.pump();
      await tester.pump(Duration(seconds: delays[i] - 1));
      expect(nativeCalls, hasLength(i));
      await tester.pump(const Duration(seconds: 1));
      expect(nativeCalls, hasLength(i + 1));
    }
    expect(logic.currentConnectionStatus, IMSdkStatus.connectionSucceeded);
    expect(logic.currentSdkStatus, IMSdkStatus.syncFailed);
    expect(nativeCalls, everyElement('setAppBackgroundStatus'));
    // A missing new failure callback must not disable retries.
    await tester.pump(const Duration(seconds: 24));
    expect(nativeCalls, hasLength(5));
    logic.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(nativeCalls, hasLength(5));
    logic.onClose();
  });

  test('sync completion cannot erase a real transport failure', () {
    logic.imSdkStatus(IMSdkStatus.connectionFailed);
    logic.imSdkStatus(IMSdkStatus.syncEnded);
    expect(logic.currentConnectionStatus, IMSdkStatus.connectionFailed);
  });

  test('cold startup does not log out an already logged-out native SDK', () {
    expect(nativeCalls, ['login:first']);
  });

  test('foreground wakes native connection without login or fake success',
      () async {
    logic.imSdkStatus(IMSdkStatus.connectionFailed);
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(nativeCalls, [
      'login:first',
      'networkStatusChanged',
      'setAppBackgroundStatus',
    ]);
    expect(logic.currentSdkStatus, IMSdkStatus.connectionFailed);
    await logic.logout();
    final afterLogout = List<String>.of(nativeCalls);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(nativeCalls, afterLogout);
  });

  for (final nativeStatus in [LoginStatus.logged, LoginStatus.logging]) {
    test('hot restart replaces orphaned native session ($nativeStatus)',
        () async {
      logic.imSdkStatus(IMSdkStatus.syncEnded);
      await restartDartSession();
      nativeStatusOverride = nativeStatus;

      await logic.login('first', 'first-im');

      expect(nativeCalls, ['login:first', 'logout:first', 'login:first']);
      // A completed login/local profile read must not manufacture readiness.
      expect(logic.currentSdkStatus, IMSdkStatus.connecting);
      logic.imSdkStatus(IMSdkStatus.connectionSucceeded);
      expect(logic.currentSdkStatus, IMSdkStatus.connectionSucceeded);
      expect(DataSp.userID, 'first');
      expect(DataSp.imToken, 'first-im');
    });
  }

  test('hot restart cannot adopt a native session belonging to another account',
      () async {
    await restartDartSession();
    await _credentials('second');

    await logic.login('second', 'second-im');

    expect(nativeCalls, ['login:first', 'logout:first', 'login:second']);
    expect(logic.userInfo.value.userID, 'second');
    expect(logic.currentSdkStatus, IMSdkStatus.connecting);
  });

  test('hot restart waits for native cleanup before starting a new login',
      () async {
    await restartDartSession();
    final finished = Completer<void>();
    cleanup = () => finished.future;
    final login = logic.login('first', 'first-im');
    await Future<void>.delayed(Duration.zero);

    expect(nativeCalls, ['login:first', 'logout:first']);
    expect(logic.currentSdkStatus, IMSdkStatus.connecting);
    finished.complete();
    await login;
    expect(nativeCalls, ['login:first', 'logout:first', 'login:first']);
  });

  test('failed orphan cleanup does not silently reuse the old native session',
      () async {
    await restartDartSession();
    cleanup = () async => throw PlatformException(code: 'cleanup-failed');

    await expectLater(
        logic.login('first', 'first-im'), throwsA(isA<PlatformException>()));

    expect(nativeCalls, ['login:first', 'logout:first']);
    expect(nativeLogged, isTrue);
    expect(OpenIM.iMManager.isLogined, isFalse);
    expect(logic.currentSdkStatus, IMSdkStatus.connecting);
  });

  for (final status in [
    IMSdkStatus.connectionSucceeded,
    IMSdkStatus.syncStart,
    IMSdkStatus.syncProgress,
    IMSdkStatus.syncEnded,
    IMSdkStatus.connectionFailed,
    IMSdkStatus.syncFailed,
  ]) {
    test(
        'reusing the same SDK session preserves $status without a new callback',
        () async {
      logic.imSdkStatus(status);
      final events = <IMSdkStatus>[];
      subscriptions.add(logic.imSdkStatusPublishSubject
          .listen((event) => events.add(event.status)));

      await logic.login('first', 'first-im');
      await Future<void>.delayed(Duration.zero);

      expect(nativeCalls, ['login:first']);
      expect(logic.currentSdkStatus, status);
      expect(events, isEmpty);
      final latest = await logic.imSdkStatusSubject.first;
      expect(latest.status, status);
    });
  }

  test('logged-in local session does not prove a live connection', () async {
    expect(nativeLogged, isTrue);
    expect(logic.currentSdkStatus, IMSdkStatus.connecting);
    logic.imSdkStatus(IMSdkStatus.syncEnded);
    logic.imSdkStatus(IMSdkStatus.connecting);

    await logic.login('first', 'first-im');

    expect(logic.currentSdkStatus, IMSdkStatus.connecting);
    logic.imSdkStatus(IMSdkStatus.connectionSucceeded);
    expect(logic.currentSdkStatus, IMSdkStatus.connectionSucceeded);
  });

  for (final next in [('second', 'second-im'), ('first', 'renewed-im')]) {
    test('new credentials $next do not inherit old ready status', () async {
      logic.imSdkStatus(IMSdkStatus.syncEnded);
      await _credentials(next.$1, token: next.$2);

      await logic.login(next.$1, next.$2);

      expect(nativeCalls, ['login:first', 'logout:first', 'login:${next.$1}']);
      expect(logic.currentSdkStatus, IMSdkStatus.connecting);
    });
  }

  test('logout then same-account login starts a new connection attempt',
      () async {
    logic.imSdkStatus(IMSdkStatus.syncEnded);
    await logic.logout();
    await logic.login('first', 'first-im');
    expect(nativeCalls, ['login:first', 'logout:first', 'login:first']);
    expect(logic.currentSdkStatus, IMSdkStatus.connecting);
  });
}
