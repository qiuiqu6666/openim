import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/account_security_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Security extends StubSettingsService {
  final pending = Completer<void>();
  @override
  bool get isSecurityBackendAvailable => true;
  @override
  Future<void> refreshSecurity() => pending.future;
}

void main() {
  test('biometric preferences persist independently for each account',
      () async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'account-a';
    await DataSp.setBiometricPay(true);
    await DataSp.putBiometricSettings('account-a', {
      'supported': true,
      'mode': 'face',
    });
    OpenIM.iMManager.userID = 'account-b';
    expect(DataSp.isEnabledBiometricPay(), false);
    expect(DataSp.getBiometricSettings('account-b'), isNull);
    await DataSp.setBiometricPay(false);
    await DataSp.putBiometricSettings('account-b', {
      'supported': false,
      'mode': '',
    });
    // An operation started by A cannot write into B after switching accounts.
    await DataSp.setBiometricPay(true, accountID: 'account-a');
    expect(DataSp.isEnabledBiometricPay(), false);
    OpenIM.iMManager.userID = 'account-a';
    await SpUtil().init();
    expect(DataSp.isEnabledBiometricPay(), true);
    expect(DataSp.getBiometricSettings('account-a')?['mode'], 'face');
    expect(DataSp.getBiometricSettings('account-b')?['supported'], false);
  });
  for (final brightness in Brightness.values) {
    for (final supported in [true, false]) {
      testWidgets(
          'security layout stays stable: $brightness, biometrics $supported',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SpUtil().init();
        OpenIM.iMManager.userID = 'layout-test-user';
        await DataSp.putBiometricSettings('layout-test-user', {
          'supported': supported,
          'mode': 'fingerprint',
        });
        final device = Completer<bool>();
        const channel = MethodChannel('plugins.flutter.io/local_auth');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          if (call.method == 'isDeviceSupported') return device.future;
          if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));
        final store = SettingsDraftStore();
        addTearDown(store.dispose);
        final service = _Security();
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(brightness: brightness),
          home: AccountSecurityPage(store: store, service: service),
        ));
        expect(find.text('登录设备'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('指纹支付'), supported ? findsOneWidget : findsNothing);
        final passwordPosition = tester.getTopLeft(find.text('修改密码'));
        final devicesPosition = tester.getTopLeft(find.text('登录设备'));
        device.complete(supported);
        await tester.pump();
        await tester.pump();
        expect(find.text('登录设备'), findsOneWidget);
        expect(find.text('指纹支付'), supported ? findsOneWidget : findsNothing);
        service.pending.complete();
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.getTopLeft(find.text('修改密码')), passwordPosition);
        expect(tester.getTopLeft(find.text('登录设备')), devicesPosition);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
