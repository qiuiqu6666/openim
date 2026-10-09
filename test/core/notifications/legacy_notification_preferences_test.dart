import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/legacy_notification_preferences.dart';
import 'package:openim/core/notifications/message_notification_preferences.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const hidden = LegacyNotificationSnapshot(
    version: 'chat99-notifications-v1',
    systemEnabled: false,
    displayMode: 'hidden');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'owner', 'imToken': 'im', 'chatToken': 'chat'}));
  });

  test(
      'hidden/system off initialize only own missing choices and survive reload',
      () async {
    final seeder = LegacyNotificationPreferenceSeeder();
    expect(
        await seeder.apply(
            owner: 'owner', snapshot: hidden, isCurrent: () => true),
        isTrue);
    await SpUtil().prefs!.reload();
    final prefs = MessageNotificationPreferences.read('owner');
    expect(prefs.notifyWhenOpen, isFalse);
    expect(prefs.notifyWhenClosed, isFalse);
    expect(prefs.openedPreview, MessageNotificationPreview.hidden);
    expect(prefs.closedPreview, MessageNotificationPreview.hidden);
    expect(prefs.messageSoundEnabled, isTrue);
    expect(prefs.vibration, isTrue);
    expect(MessageNotificationPreferences.read('other').notifyWhenOpen, isTrue);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    expect(store.openedNotificationPreview, 'hidden');
    expect(store.callRingtoneEnabled, isTrue);
    store.updateNotifications(opened: true, openedPreview: 'detail');
    expect(
        await seeder.apply(
            owner: 'owner', snapshot: hidden, isCurrent: () => true),
        isTrue);
    expect(MessageNotificationPreferences.read('owner').notifyWhenOpen, isTrue);
    expect(MessageNotificationPreferences.read('owner').openedPreview,
        MessageNotificationPreview.detail);
  });

  test('generic stays anonymous and existing owner edits always win', () async {
    await SpUtil()
        .putString('99chat_settings_owner_notify_open_preview', 'sender');
    await LegacyNotificationPreferenceSeeder().apply(
        owner: 'owner',
        snapshot: const LegacyNotificationSnapshot(
            version: 'chat99-notifications-v1',
            systemEnabled: true,
            displayMode: 'generic'),
        isCurrent: () => true);
    expect(MessageNotificationPreferences.read('owner').openedPreview,
        MessageNotificationPreview.sender);
    expect(MessageNotificationPreferences.read('owner').closedPreview,
        MessageNotificationPreview.none);
  });

  test('an already open settings store reflects its own late snapshot only',
      () async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    expect(store.openedNotificationPreview, 'detail');
    await LegacyNotificationPreferenceSeeder()
        .apply(owner: 'owner', snapshot: hidden, isCurrent: () => true);
    MessageNotificationPreferences.notifyChanged('other');
    await Future<void>.delayed(Duration.zero);
    expect(store.openedNotificationPreview, 'detail');
    MessageNotificationPreferences.notifyChanged('owner');
    await Future<void>.delayed(Duration.zero);
    expect(store.openedNotificationPreview, 'hidden');
    expect(store.notifyWhenOpen, isFalse);
  });

  test('new accounts do not receive a migration seed', () async {
    expect(
        await LegacyNotificationPreferenceSeeder()
            .apply(owner: 'owner', snapshot: null, isCurrent: () => true),
        isTrue);
    expect(SpUtil().getDynamic(legacyNotificationSeedKey('owner')), isNull);
    expect(MessageNotificationPreferences.read('owner').closedPreview,
        MessageNotificationPreview.detail);
  });

  test('stale account token endpoint callback never grants readiness',
      () async {
    var current = true;
    final pending = Completer<bool>();
    final writes = <String>[];
    final seeder = LegacyNotificationPreferenceSeeder(
        read: (_) => null,
        write: (key, value) {
          writes.add(key);
          return pending.future;
        });
    final future = seeder.apply(
        owner: 'owner', snapshot: hidden, isCurrent: () => current);
    current = false;
    pending.complete(true);
    expect(await future, isFalse);
    expect(writes, [legacyNotificationSeedKey('owner')]);
    expect(
        await seeder.apply(
            owner: 'other', snapshot: hidden, isCurrent: () => false),
        isFalse);
    expect(writes.length, 1);
  });

  test('failed durable write remains unready and retries despite memory cache',
      () async {
    Object? cached;
    var writes = 0;
    final seeder = LegacyNotificationPreferenceSeeder(
        read: (_) => cached,
        write: (key, value) async {
          cached = value;
          return ++writes > 1;
        });
    expect(
        await seeder.apply(
            owner: 'owner', snapshot: hidden, isCurrent: () => true),
        isFalse);
    expect(
        await seeder.apply(
            owner: 'owner', snapshot: hidden, isCurrent: () => true),
        isTrue);
    expect(writes, 2);
    expect(
        await seeder.apply(
            owner: 'owner', snapshot: hidden, isCurrent: () => true),
        isTrue);
    expect(writes, 2);
  });

  test('invalid server snapshot never silently broadens privacy', () {
    for (final value in [null, 0, 'false']) {
      expect(
          () => UserFullInfo.fromJson({
                'userID': 'owner',
                'legacyNotificationSnapshot': {
                  'version': hidden.version,
                  'systemEnabled': value,
                  'displayMode': 'hidden'
                }
              }),
          throwsFormatException);
    }
    expect(
        () => LegacyNotificationSnapshot.fromJson({
              'version': hidden.version,
              'systemEnabled': false,
              'displayMode': 'unknown'
            }),
        throwsFormatException);
    expect(
        UserFullInfo.fromJson({
          'userID': 'owner',
          'legacyNotificationSnapshot': jsonDecode(jsonEncode(hidden.toJson()))
        }).legacyNotificationSnapshot!.systemEnabled,
        isFalse);
  });
}
