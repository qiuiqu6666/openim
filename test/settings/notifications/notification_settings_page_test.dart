import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notification_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetNotificationTestAccount);

  testWidgets(
      'local notification controls save without invoking a stub service',
      (tester) async {
    final store = _store();
    final service = TestNotificationService()..remote = false;
    await pumpNotificationPage(tester, store: store, service: service);
    _switch(tester, 'notification-closed-enabled').onChanged!(false);
    _switch(tester, 'notification-call-quick-answer').onChanged!(false);
    _switch(tester, 'notification-quick-reply').onChanged!(false);
    await tester.pumpAndSettle();
    expect(store.notifyWhenClosed, isFalse);
    expect(store.quickAnswer, isFalse);
    expect(store.notificationQuickReply, isFalse);
    expect(service.closedCalls, 0);
    await tapNotificationRow(tester, 'notification-closed-preview');
    await tester.tap(find.text('仅显示发送人'));
    await tester.pumpAndSettle();
    expect(store.closedNotificationPreview, 'sender');
    expect(service.previewCalls, 0);
    expect(
        SpUtil().getString(
            '99chat_settings_notification-owner_notify_closed_preview'),
        'sender');
  });

  testWidgets(
      'remote update waits for confirmation and suppresses duplicate taps',
      (tester) async {
    final store = _store();
    final pending = Completer<void>();
    final service = TestNotificationService()
      ..closedResponse = (_) => pending.future;
    await pumpNotificationPage(tester, store: store, service: service);
    final callback = _switch(tester, 'notification-closed-enabled').onChanged!;
    callback(false);
    callback(false);
    await tester.pump();
    expect(service.closedCalls, 1);
    expect(store.notifyWhenClosed, isTrue);
    expect(_switch(tester, 'notification-closed-enabled').enabled, isFalse);
    expect(notificationKey('notification-saving'), findsOneWidget);
    expect(
        tester
            .widget<SettingsCell>(
                notificationKey('notification-closed-preview'))
            .enabled,
        isFalse);
    pending.complete();
    await tester.pumpAndSettle();
    expect(store.notifyWhenClosed, isFalse);
    expect(notificationKey('notification-saving'), findsNothing);
  });

  testWidgets(
      'remote failure keeps the previous setting and exposes retryable error',
      (tester) async {
    final store = _store();
    final service = TestNotificationService()
      ..closedResponse = (_) => Future.error(StateError('test failure'));
    await pumpNotificationPage(tester, store: store, service: service);
    _switch(tester, 'notification-closed-enabled').onChanged!(false);
    await tester.pumpAndSettle();
    expect(store.notifyWhenClosed, isTrue);
    expect(notificationKey('notification-save-error'), findsOneWidget);
    expect(find.text('保存失败，请稍后重试。'), findsOneWidget);
    service.closedResponse = null;
    _switch(tester, 'notification-closed-enabled').onChanged!(false);
    await tester.pumpAndSettle();
    expect(store.notifyWhenClosed, isFalse);
    expect(notificationKey('notification-save-error'), findsNothing);
  });

  testWidgets('pending remote response cannot write after route disposal',
      (tester) async {
    final store = _store();
    final pending = Completer<void>();
    final service = TestNotificationService()
      ..closedResponse = (_) => pending.future;
    await pumpNotificationPage(tester, store: store, service: service);
    _switch(tester, 'notification-closed-enabled').onChanged!(false);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pumpAndSettle();
    expect(store.notifyWhenClosed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending remote response cannot write another account preferences',
      (tester) async {
    final store = _store();
    final pending = Completer<void>();
    final service = TestNotificationService()
      ..closedResponse = (_) => pending.future;
    await pumpNotificationPage(tester, store: store, service: service);
    _switch(tester, 'notification-closed-enabled').onChanged!(false);
    await loginNotificationTestAccount('notification-other');
    pending.complete();
    await tester.pumpAndSettle();
    expect(store.notifyWhenClosed, isTrue);
    expect(
        SpUtil().getDynamic(
            '99chat_settings_notification-other_notify_when_closed'),
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dependent content and sound rows preserve values when disabled',
      (tester) async {
    final store = _store()
      ..updateNotifications(openedPreview: 'sender', messageSound: 'crisp');
    await pumpNotificationPage(tester, store: store);
    await tester.scrollUntilVisible(
        notificationKey('notification-message-sound-enabled'), 120,
        scrollable: find.byType(Scrollable).first);
    _switch(tester, 'notification-open-enabled').onChanged!(false);
    _switch(tester, 'notification-message-sound-enabled').onChanged!(false);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SettingsCell>(notificationKey('notification-open-preview'))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<SettingsCell>(notificationKey('notification-message-sound'))
            .enabled,
        isFalse);
    await tapNotificationRow(tester, 'notification-open-preview');
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(store.openedNotificationPreview, 'sender');
    expect(store.messageSound, 'crisp');
    _switch(tester, 'notification-open-enabled').onChanged!(true);
    await tester.pumpAndSettle();
    await tapNotificationRow(tester, 'notification-open-preview');
    await tester.tap(find.text('不显示详情'));
    await tester.pumpAndSettle();
    expect(store.openedNotificationPreview, 'none');
  });

  testWidgets('all foreground alert switches update independently',
      (tester) async {
    final store = _store();
    await pumpNotificationPage(tester, store: store);
    await tester.scrollUntilVisible(
        notificationKey('notification-vibration'), 120,
        scrollable: find.byType(Scrollable).first);
    _switch(tester, 'notification-message-sound-enabled').onChanged!(false);
    _switch(tester, 'notification-call-ringtone').onChanged!(false);
    _switch(tester, 'notification-vibration').onChanged!(false);
    await tester.pumpAndSettle();
    expect(store.messageSoundEnabled, isFalse);
    expect(store.callRingtoneEnabled, isFalse);
    expect(store.vibration, isFalse);
    expect(store.notifyWhenOpen, isTrue);
    expect(store.quickAnswer, isTrue);
    expect(store.notificationQuickReply, isTrue);
  });

  testWidgets(
      'permission request disables both actions and resumes current status',
      (tester) async {
    final store = _store();
    final pending = Completer<PermissionStatus>();
    final permission = TestNotificationPermissionGateway()
      ..permission = PermissionStatus.denied
      ..requestResponse = () => pending.future;
    await pumpNotificationPage(tester, store: store, permission: permission);
    final button = tester
        .widget<TextButton>(notificationKey('notification-permission-enable'));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(permission.requestCalls, 1);
    expect(
        tester
            .widget<TextButton>(
                notificationKey('notification-permission-settings'))
            .onPressed,
        isNull);
    pending.complete(PermissionStatus.granted);
    await tester.pumpAndSettle();
    expect(notificationKey('notification-permission-message'), findsNothing);
    permission.permission = PermissionStatus.denied;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(notificationKey('notification-permission-message'), findsOneWidget);
  });

  testWidgets('permanent denial opens settings and failed launch is actionable',
      (tester) async {
    final store = _store();
    final permission = TestNotificationPermissionGateway()
      ..permission = PermissionStatus.denied
      ..settingsOpened = false
      ..requestResponse = () async => PermissionStatus.permanentlyDenied;
    await pumpNotificationPage(tester, store: store, permission: permission);
    await tester.tap(notificationKey('notification-permission-enable'));
    await tester.pumpAndSettle();
    expect(permission.settingsCalls, 1);
    expect(find.textContaining('无法开启系统通知权限'), findsOneWidget);
    expect(notificationKey('notification-permission-retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'permission status failure can be retried without hiding the error',
      (tester) async {
    final store = _store();
    final permission = TestNotificationPermissionGateway()
      ..statusError = StateError('test status failure');
    await pumpNotificationPage(tester, store: store, permission: permission);
    expect(find.textContaining('无法读取系统通知权限'), findsOneWidget);
    permission.statusError = null;
    await tester.tap(notificationKey('notification-permission-retry'));
    await tester.pumpAndSettle();
    expect(notificationKey('notification-permission-message'), findsNothing);
  });

  testWidgets(
      'permission request completion cannot open settings after disposal',
      (tester) async {
    final store = _store();
    final pending = Completer<PermissionStatus>();
    final permission = TestNotificationPermissionGateway()
      ..permission = PermissionStatus.denied
      ..requestResponse = () => pending.future;
    await pumpNotificationPage(tester, store: store, permission: permission);
    await tester.tap(notificationKey('notification-permission-enable'));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(PermissionStatus.permanentlyDenied);
    await tester.pumpAndSettle();
    expect(permission.settingsCalls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(844, 390)]) {
      testWidgets(
          'notification rows fit ${brightness.name} $size and large text',
          (tester) async {
        final store = _store();
        final permission = TestNotificationPermissionGateway()
          ..permission = PermissionStatus.denied;
        await pumpNotificationPage(tester,
            store: store,
            permission: permission,
            size: size,
            brightness: brightness,
            locale: const Locale('en', 'US'),
            textScale: 1.8);
        await tester.scrollUntilVisible(
            notificationKey('notification-vibration'), 150,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

SettingsDraftStore _store() {
  final store = SettingsDraftStore();
  addTearDown(store.dispose);
  return store;
}

SettingsSwitchCell _switch(WidgetTester tester, String key) =>
    tester.widget<SettingsSwitchCell>(notificationKey(key));
