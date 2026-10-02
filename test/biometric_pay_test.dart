import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_android/local_auth_android.dart' show AuthMessages;
import 'package:openim/pages/mine/settings/pages/biometric_pay_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends LocalAuthentication {
  _Auth(this.types, this.success, {this.supported = true, this.errorCode});
  final List<BiometricType> types;
  final bool success;
  final bool supported;
  final String? errorCode;
  int calls = 0;
  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<bool> get canCheckBiometrics async => true;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => types;
  @override
  Future<bool> authenticate(
      {required String localizedReason,
      Iterable<AuthMessages> authMessages = const [],
      AuthenticationOptions options = const AuthenticationOptions()}) async {
    expect(options.biometricOnly, true);
    calls++;
    if (errorCode != null) throw PlatformException(code: errorCode!);
    return success;
  }
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scenario in [
      'success',
      'cancel',
      'not enrolled',
      'unsupported',
      'locked'
    ]) {
      testWidgets('$platform biometric payment $scenario', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        SharedPreferences.setMockInitialValues({});
        await SpUtil().init();
        OpenIM.iMManager.userInfo = UserInfo(userID: 'test-user');
        OpenIM.iMManager.userID = 'test-user';
        await DataSp.openBiometric();
        final store = SettingsDraftStore();
        addTearDown(store.dispose);
        final auth = _Auth(
            scenario == 'not enrolled'
                ? []
                : [
                    platform == TargetPlatform.iOS
                        ? BiometricType.face
                        : BiometricType.fingerprint
                  ],
            scenario == 'success',
            supported: scenario != 'unsupported',
            errorCode: scenario == 'locked' ? 'LockedOut' : null);
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => GetMaterialApp(
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [Locale('zh', 'CN')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: EasyLoading.init(),
                home: BiometricPayPage(store: store, authentication: auth))));
        await tester.pumpAndSettle();
        expect(store.biometricPay, false);
        await tester.tap(find.textContaining('开启手机').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(store.biometricPay, scenario == 'success');
        expect(DataSp.isEnabledBiometricPay(), scenario == 'success');
        expect(DataSp.isEnabledBiometric(), true);
        expect(auth.calls,
            scenario == 'not enrolled' || scenario == 'unsupported' ? 0 : 1);
        if (scenario == 'locked') {
          expect(find.text('尝试次数过多，请稍后再试'), findsOneWidget);
        }
        if (scenario == 'not enrolled') {
          expect(find.text('未设置生物识别'), findsOneWidget);
          Get.back();
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        if (scenario == 'success') {
          await tester.tap(find.textContaining('关闭手机').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('关闭'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(DataSp.isEnabledBiometricPay(), false);
          expect(DataSp.isEnabledBiometric(), true);
        }
        await tester.pumpWidget(const SizedBox());
        await EasyLoading.dismiss(animation: false);
        Get.reset();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
