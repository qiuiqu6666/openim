import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Callbacks extends GetxController with IMCallback {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Callbacks callbacks;
  Future<void> credentials(String user, String token) async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': user, 'imToken': 'im', 'chatToken': token}));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await credentials('self', 'session-one');
    Get.testMode = true;
    Get.put<AppController>(_App());
    callbacks = _Callbacks();
  });
  tearDown(() async {
    callbacks.close();
    Get.reset();
  });

  test('initial sync must finish but later incremental failures do not mute',
      () {
    callbacks.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
    callbacks.imSdkStatus(IMSdkStatus.syncFailed);
    expect(callbacks.notificationSessionReady, isFalse);
    callbacks.imSdkStatus(IMSdkStatus.syncEnded);
    for (final state in [
      IMSdkStatus.connecting,
      IMSdkStatus.connectionFailed,
      IMSdkStatus.connectionSucceeded,
      IMSdkStatus.syncStart,
      IMSdkStatus.syncProgress,
      IMSdkStatus.syncFailed
    ]) {
      callbacks.imSdkStatus(state);
      expect(callbacks.notificationSessionReady, isTrue, reason: '$state');
    }
  });

  test('new credentials and explicit logout cannot inherit readiness',
      () async {
    callbacks.imSdkStatus(IMSdkStatus.syncEnded);
    await credentials('self', 'session-two');
    expect(callbacks.notificationSessionReady, isFalse);
    callbacks.imSdkStatus(IMSdkStatus.syncEnded);
    await credentials('other', 'session-two');
    expect(callbacks.notificationSessionReady, isFalse);
    callbacks.imSdkStatus(IMSdkStatus.syncEnded);
    callbacks.resetNotificationReadiness();
    expect(callbacks.notificationSessionReady, isFalse);
  });

  test('authenticated profile enables live alerts despite failed initial sync', () {
    callbacks.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
    callbacks.imSdkStatus(IMSdkStatus.syncFailed);
    expect(callbacks.notificationSessionReady, isFalse);
    callbacks.markNotificationSessionReady('other', 'session-one');
    callbacks.markNotificationSessionReady('self', 'old-token');
    expect(callbacks.notificationSessionReady, isFalse);
    callbacks.markNotificationSessionReady('self', 'session-one');
    expect(callbacks.notificationSessionReady, isTrue);
    callbacks.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
    callbacks.imSdkStatus(IMSdkStatus.syncFailed);
    expect(callbacks.notificationSessionReady, isTrue);
  });

  test('expired credentials revoke readiness', () {
    for (final invalidate in [
      callbacks.kickedOffline,
      callbacks.userTokenInvalid,
      callbacks.userTokenExpired,
    ]) {
      callbacks.imSdkStatus(IMSdkStatus.syncEnded);
      invalidate();
      expect(callbacks.notificationSessionReady, isFalse);
    }
  });
}
