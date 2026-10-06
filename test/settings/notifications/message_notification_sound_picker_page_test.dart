import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/notifications/message_notification_sound_picker_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim/core/notifications/notification_sound_activity.dart';

import 'notification_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetNotificationTestAccount);

  testWidgets('selection persists and only the latest queued sound plays',
      (tester) async {
    final store = _store();
    final firstLoad = Completer<void>();
    final preview = TestNotificationSoundPreview()
      ..loadResponse =
          (id) => id == 'crisp' ? firstLoad.future : Future<void>.value();
    await _pump(tester, store, preview);
    await tapNotificationRow(tester, 'notification-sound-crisp');
    expect(store.messageSound, 'crisp');
    expect(preview.loadedIds, ['crisp']);
    await tapNotificationRow(tester, 'notification-sound-soft');
    await tapNotificationRow(tester, 'notification-sound-chime');
    firstLoad.complete();
    await tester.pumpAndSettle();
    expect(store.messageSound, 'chime');
    expect(preview.playedIds, ['chime']);
    expect(preview.loadedIds, ['crisp', 'chime']);
  });

  testWidgets('failed preview keeps the saved selection and shows an error',
      (tester) async {
    final store = _store();
    final preview = TestNotificationSoundPreview()
      ..loadResponse = (_) => Future.error(StateError('test audio failure'));
    await _pump(tester, store, preview);
    await tapNotificationRow(tester, 'notification-sound-soft');
    expect(store.messageSound, 'soft');
    expect(notificationKey('notification-sound-preview-error'), findsOneWidget);
    expect(preview.playedIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending load cannot play after the picker is disposed',
      (tester) async {
    final store = _store();
    final pending = Completer<void>();
    final preview = TestNotificationSoundPreview()
      ..loadResponse = (_) => pending.future;
    await _pump(tester, store, preview);
    await tapNotificationRow(tester, 'notification-sound-crisp');
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pumpAndSettle();
    expect(preview.playedIds, isEmpty);
    expect(preview.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a call interruption stops preview immediately during load', (tester) async {
    final store = _store();
    final pending = Completer<void>();
    final preview = TestNotificationSoundPreview()..loadResponse = (_) => pending.future;
    await _pump(tester, store, preview);
    await tapNotificationRow(tester, 'notification-sound-crisp');
    final previousStops = preview.stopCalls;
    NotificationSoundActivity.interruptPreviews();
    await tester.pump();
    expect(preview.stopCalls, greaterThan(previousStops));
    pending.complete();
    await tester.pumpAndSettle();
    expect(preview.playedIds, isEmpty);
    expect(store.messageSound, 'crisp');
  });

  testWidgets('a pending load cannot play after an account switch',
      (tester) async {
    final store = _store();
    final pending = Completer<void>();
    final preview = TestNotificationSoundPreview()
      ..loadResponse = (_) => pending.future;
    await _pump(tester, store, preview);
    await tapNotificationRow(tester, 'notification-sound-crisp');
    await loginNotificationTestAccount('notification-other');
    pending.complete();
    await tester.pumpAndSettle();
    expect(preview.playedIds, isEmpty);
    await tapNotificationRow(tester, 'notification-sound-soft');
    expect(store.messageSound, 'crisp');
  });

  testWidgets(
      'an active call allows choosing a sound without taking its audio route',
      (tester) async {
    final store = _store();
    final preview = TestNotificationSoundPreview();
    await pumpNotificationPage(tester,
        store: store,
        page: MessageNotificationSoundPickerPage(
            store: store, preview: preview, isCallActive: () => true));
    await tapNotificationRow(tester, 'notification-sound-crisp');
    expect(store.messageSound, 'crisp');
    expect(preview.loadedIds, isEmpty);
    expect(preview.playedIds, isEmpty);
    expect(find.text('提示音已选择，请在通话结束后试听。'), findsOneWidget);
  });

  testWidgets(
      'disabled sound preference prevents changes on an existing picker',
      (tester) async {
    final store = _store()..updateNotifications(messageSoundEnabled: false);
    final preview = TestNotificationSoundPreview();
    await _pump(tester, store, preview);
    expect(
        tester
            .widget<SettingsCell>(notificationKey('notification-sound-crisp'))
            .enabled,
        isFalse);
    await tapNotificationRow(tester, 'notification-sound-crisp');
    expect(store.messageSound, 'preview000');
    expect(preview.loadedIds, isEmpty);
  });
}

Future<void> _pump(WidgetTester tester, SettingsDraftStore store,
        TestNotificationSoundPreview preview) =>
    pumpNotificationPage(tester,
        store: store,
        page: MessageNotificationSoundPickerPage(
            store: store, preview: preview, isCallActive: () => false));

SettingsDraftStore _store() {
  final store = SettingsDraftStore();
  addTearDown(store.dispose);
  return store;
}
