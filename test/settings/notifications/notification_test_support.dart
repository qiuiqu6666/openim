import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/notifications/message_notification_sound_preview.dart';
import 'package:openim/pages/mine/settings/notifications/notification_permission_gateway.dart';
import 'package:openim/pages/mine/settings/notifications/notification_settings_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> resetNotificationTestAccount() async {
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
  await loginNotificationTestAccount('notification-owner');
}

Future<void> loginNotificationTestAccount(String owner) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': owner,
    'chatToken': 'test-chat-token',
    'imToken': 'test-im-token',
  }));
}

class TestNotificationService extends StubSettingsService {
  int closedCalls = 0;
  int previewCalls = 0;
  bool remote = true;
  Future<void> Function(bool)? closedResponse;
  Future<void> Function(String)? previewResponse;

  @override
  bool get supportsRemoteNotificationSettings => remote;

  @override
  Future<void> updateSystemMessageNotification(bool enabled) {
    closedCalls++;
    return closedResponse?.call(enabled) ?? Future<void>.value();
  }

  @override
  Future<void> updateClosedNotificationPreview(String preview) {
    previewCalls++;
    return previewResponse?.call(preview) ?? Future<void>.value();
  }
}

class TestNotificationPermissionGateway extends NotificationPermissionGateway {
  PermissionStatus permission = PermissionStatus.granted;
  Object? statusError;
  int requestCalls = 0;
  int settingsCalls = 0;
  int statusCalls = 0;
  bool settingsOpened = true;
  Future<PermissionStatus> Function()? requestResponse;

  @override
  Future<PermissionStatus?> status() async {
    statusCalls++;
    if (statusError != null) throw statusError!;
    return permission;
  }

  @override
  Future<PermissionStatus> request() async {
    requestCalls++;
    final result = await (requestResponse?.call() ??
        Future.value(PermissionStatus.granted));
    permission = result;
    return result;
  }

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return settingsOpened;
  }
}

class TestNotificationSoundPreview implements MessageNotificationSoundPreview {
  String? loaded;
  final loadedIds = <String>[];
  final playedIds = <String>[];
  int stopCalls = 0;
  int disposeCalls = 0;
  Future<void> Function(String)? loadResponse;

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> load(String id) async {
    loadedIds.add(id);
    await loadResponse?.call(id);
    loaded = id;
  }

  @override
  Future<void> play() async {
    playedIds.add(loaded!);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

Future<void> pumpNotificationPage(
  WidgetTester tester, {
  required SettingsDraftStore store,
  SettingsService service = const StubSettingsService(),
  TestNotificationPermissionGateway? permission,
  Widget? page,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
  GlobalKey? boundaryKey,
  String? fontFamily,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final dark = brightness == Brightness.dark;
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: brightness,
        platform: TargetPlatform.android,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTokens.accent,
          brightness: brightness,
          surface: AppTokens.surface(dark: dark),
        ),
        scaffoldBackgroundColor: AppTokens.background(dark: dark),
        cupertinoOverrideTheme: CupertinoThemeData(
          brightness: brightness,
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(fontFamily: fontFamily),
            actionTextStyle: TextStyle(fontFamily: fontFamily),
          ),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(key: boundaryKey, child: child!),
      ),
      home: page ??
          NotificationSettingsPage(
            store: store,
            service: service,
            permissionGateway:
                permission ?? TestNotificationPermissionGateway(),
          ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder notificationKey(String key) => find.byKey(ValueKey(key));

Future<void> tapNotificationRow(WidgetTester tester, String key) async {
  final row = notificationKey(key);
  await tester.scrollUntilVisible(row, 100,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(row);
  await tester.pumpAndSettle();
}
