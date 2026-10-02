import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/login_devices_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';

class _Devices extends StubSettingsService {
  final records = <Map<String, dynamic>>[
    {
      'deviceID': 'other',
      'deviceName': 'Samsung SM-N9810',
      'platform': 'Android',
      'version': '3.8.3',
      'online': true,
      'trusted': true,
      'ip': '103.119.97.240',
      'loginTime': 1790956021000
    },
    {
      'deviceID': DataSp.getDeviceID(),
      'deviceName': 'Web',
      'platform': 'Web',
      'ip': '127.0.0.1',
      'loginTime': 1790956021000
    },
    {
      'deviceID': 'iphone',
      'deviceName': 'iPhone',
      'platform': 'iOS',
      'ip': '154.197.63.250'
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> getLoginRecords() async => records;
  @override
  Future<void> trustDevice(String deviceID, bool trusted) async {
    records.firstWhere((r) => r['deviceID'] == deviceID)['trusted'] = trusted;
  }

  @override
  Future<void> removeOtherDevices() async {
    records.removeWhere((r) => r['deviceID'] != DataSp.getDeviceID());
  }

  @override
  Future<void> removeDevice(String deviceID) async {
    records.removeWhere((r) => r['deviceID'] == deviceID);
  }
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'login device metadata fits narrow large-text screen, dark=$dark',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SpUtil().init();
      final service = _Devices();
      service.records.addAll([
        {'deviceName': 'Legacy missing UUID'},
        {'deviceID': '', 'deviceName': 'Legacy empty UUID'},
      ]);
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousDark = Styles.isDark;
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = previousDark);
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              home: LoginDevicesPage(service: service))));
      await tester.pumpAndSettle();
      expect(find.text('Samsung SM-N9810'), findsOneWidget);
      expect(find.text('3.8.3'), findsOneWidget);
      expect(find.text('在线'), findsOneWidget);
      expect(find.text('已信任'), findsOneWidget);
      expect(find.text('103.119.97.240'), findsOneWidget);
      expect(find.byIcon(Icons.phone_android_rounded), findsOneWidget);
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
      expect(find.byIcon(Icons.phone_iphone_rounded), findsOneWidget);
      expect(find.text('Legacy missing UUID'), findsNothing);
      expect(find.text('Legacy empty UUID'), findsNothing);
      expect(find.text('本机'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(find.byType(PopupMenuButton<bool>), findsNothing);
      await tester.tap(find.text('移除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.records.length, 5);
      await tester.tap(find.text('移除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除').last);
      await tester.pumpAndSettle();
      expect(service.records.length, 4);
      expect(find.text('Samsung SM-N9810'), findsNothing);
      expect(find.text('本机'), findsOneWidget);
      await tester.tap(find.text('移除其他设备'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除').last);
      await tester.pumpAndSettle();
      expect(service.records.length, 1);
      expect(find.text('本机'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
