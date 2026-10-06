import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/device_sync/device_sync_runtime.dart';
import 'package:openim/pages/mine/settings/device_sync/device_sync_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_home_page.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Runtime implements DeviceSyncRuntime {
  _Runtime({DeviceSyncPreferences? initial})
      : preferences = ValueNotifier(
            initial ?? DeviceSyncPreferences.fromJson('account-a', null));

  @override
  final ValueNotifier<DeviceSyncPreferences> preferences;
  @override
  final ValueNotifier<DeviceSyncStatus> status =
      ValueNotifier(DeviceSyncStatus.inactive);
  final writes = <Map<String, bool?>>[];
  Completer<void>? pending;

  @override
  Future<void> setPreferences(
      {bool? photos, bool? videos, bool? location, bool? wifiOnly}) async {
    writes.add({
      'photos': photos,
      'videos': videos,
      'location': location,
      'wifiOnly': wifiOnly,
    });
    await pending?.future;
    preferences.value = preferences.value.copyWith(
        photos: photos, videos: videos, location: location, wifiOnly: wifiOnly);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void close() {
    preferences.dispose();
    status.dispose();
  }
}

Widget _host(Widget child,
        {Brightness brightness = Brightness.light, double scale = 1}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24, bottom: 34)),
          child: child!,
        ),
        home: child,
      ),
    );

Future<void> _toggle(WidgetTester tester, String key) async {
  final cell = find.byKey(ValueKey(key));
  await tester.ensureVisible(cell);
  await tester.tap(
      find.descendant(of: cell, matching: find.byType(SettingsPlatformSwitch)));
  await tester.pump();
}

Future<void> _signIn(String owner) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': owner,
    'imToken': 'fixture-im-token',
    'chatToken': 'fixture-chat-token',
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _signIn('account-a');
  });

  testWidgets('settings exposes an explicit device-sync entry', (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(SettingsHomePage(store: store)));
    expect(find.byKey(const ValueKey('settings-device-sync')), findsOneWidget);
    expect(find.text('相册与定位同步'), findsOneWidget);
  });

  testWidgets('photo and login location choices remain independent',
      (tester) async {
    final runtime = _Runtime(
        initial: const DeviceSyncPreferences(
            accountID: 'account-a', photos: false, location: false));
    addTearDown(runtime.close);
    await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime)));
    await _toggle(tester, 'device-sync-photos');
    await tester.pump();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(runtime.preferences.value.photos, isTrue);
    expect(runtime.preferences.value.location, isFalse);
    expect(runtime.preferences.value.videos, isFalse);
    await _toggle(tester, 'device-sync-location');
    await tester.pump();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(runtime.preferences.value.location, isTrue);
    expect(runtime.preferences.value.wifiOnly, isTrue);
    expect(find.textContaining('仅存于 iCloud'), findsOneWidget);
    expect(find.textContaining('10 秒内无结果'), findsOneWidget);
    runtime.status.value = DeviceSyncStatus.uploading;
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const ValueKey('device-sync-status')));
    expect(find.text('正在上传'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'videos require a separate confirmation and cancel writes nothing',
      (tester) async {
    final runtime = _Runtime(
        initial:
            const DeviceSyncPreferences(accountID: 'account-a', photos: true));
    addTearDown(runtime.close);
    await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime)));
    await _toggle(tester, 'device-sync-videos');
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(runtime.writes, isEmpty);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消'));
    await tester.pumpAndSettle();
    expect(runtime.writes, isEmpty);
    expect(runtime.preferences.value.videos, isFalse);
    await _toggle(tester, 'device-sync-videos');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '开启视频上传'));
    await tester.pumpAndSettle();
    expect(runtime.preferences.value.videos, isTrue);
    await _toggle(tester, 'device-sync-photos');
    await tester.pump();
    expect(runtime.preferences.value.photos, isFalse);
    expect(runtime.preferences.value.videos, isFalse);
  });

  testWidgets(
      'account switch during confirmation cannot save into the new account',
      (tester) async {
    final runtime = _Runtime(
        initial:
            const DeviceSyncPreferences(accountID: 'account-a', photos: true));
    addTearDown(runtime.close);
    await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime)));
    await _toggle(tester, 'device-sync-videos');
    await tester.pumpAndSettle();
    runtime.preferences.value =
        const DeviceSyncPreferences(accountID: 'account-b');
    await tester.pump();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '开启视频上传'));
    await tester.pumpAndSettle();
    expect(runtime.writes, isEmpty);
    expect(find.text('登录账号已变化，请重新打开此页面。'), findsOneWidget);
  });

  testWidgets('pending preference save prevents repeated toggles',
      (tester) async {
    final runtime = _Runtime(
        initial: const DeviceSyncPreferences(
            accountID: 'account-a', photos: false, location: false))
      ..pending = Completer<void>();
    addTearDown(runtime.close);
    await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime)));
    await _toggle(tester, 'device-sync-photos');
    await _toggle(tester, 'device-sync-location');
    expect(runtime.writes, hasLength(1));
    runtime.pending!.complete();
    await tester.pumpAndSettle();
    expect(runtime.preferences.value.photos, isTrue);
    expect(runtime.preferences.value.location, isFalse);
  });

  testWidgets('system permissions open only after an explicit settings action',
      (tester) async {
    final runtime = _Runtime();
    addTearDown(runtime.close);
    var opens = 0;
    await tester.pumpWidget(_host(DeviceSyncPage(
        runtime: runtime,
        onOpenSystemSettings: () async {
          opens++;
          return true;
        })));
    expect(opens, 0);
    final cell = find.byKey(const ValueKey('device-sync-system-settings'));
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(runtime.writes, isEmpty);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          '320px sync settings remain scrollable: $brightness, scale $scale',
          (tester) async {
        tester.view.physicalSize = const Size(320, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final runtime = _Runtime();
        addTearDown(runtime.close);
        await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime),
            brightness: brightness, scale: scale));
        expect(find.text('照片自动上传'), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ListView), findsOneWidget);
      });
    }
  }

  testWidgets('new accounts show all four switches on without a dialog',
      (tester) async {
    final runtime = _Runtime();
    addTearDown(runtime.close);
    await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SettingsSwitchCell>(
                find.byKey(const ValueKey('device-sync-photos')))
            .value,
        isTrue);
    expect(
        tester
            .widget<SettingsSwitchCell>(
                find.byKey(const ValueKey('device-sync-location')))
            .value,
        isTrue);
    expect(
        tester
            .widget<SettingsSwitchCell>(
                find.byKey(const ValueKey('device-sync-videos')))
            .value,
        isTrue);
    await tester
        .ensureVisible(find.byKey(const ValueKey('device-sync-wifi-only')));
    expect(
        tester
            .widget<SettingsSwitchCell>(
                find.byKey(const ValueKey('device-sync-wifi-only')))
            .value,
        isTrue);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(runtime.writes, isEmpty);
  });

  testWidgets('default photos and location can be disabled independently',
      (tester) async {
    final runtime = _Runtime();
    addTearDown(runtime.close);
    await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime)));
    await _toggle(tester, 'device-sync-photos');
    await tester.pumpAndSettle();
    expect(runtime.preferences.value.photos, isFalse);
    expect(runtime.preferences.value.location, isTrue);
    await _toggle(tester, 'device-sync-location');
    await tester.pumpAndSettle();
    expect(runtime.preferences.value.photos, isFalse);
    expect(runtime.preferences.value.location, isFalse);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(runtime.writes, hasLength(2));
  });

  testWidgets('account changes disable direct sync choices', (tester) async {
    final runtime = _Runtime();
    addTearDown(runtime.close);
    await tester.pumpWidget(_host(DeviceSyncPage(runtime: runtime)));
    runtime.preferences.value =
        DeviceSyncPreferences.fromJson('account-b', null);
    await tester.pump();
    await _toggle(tester, 'device-sync-photos');
    await _toggle(tester, 'device-sync-location');
    expect(runtime.writes, isEmpty);
    expect(runtime.preferences.value.photos, isTrue);
    expect(runtime.preferences.value.location, isTrue);
    expect(find.text('登录账号已变化，请重新打开此页面。'), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });
}
