import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/message_notification_preferences.dart';
import 'package:openim/core/notifications/message_notification_sound.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await _login('owner');
  });

  test('new accounts retain independent notification and call defaults', () {
    final store = _store();
    expect(store.notifyWhenClosed, isTrue);
    expect(store.closedNotificationPreview, 'detail');
    expect(store.notificationQuickReply, isTrue);
    expect(store.quickAnswer, isTrue);
    expect(store.callNotifyWhenClosed, isTrue);
    final preferences = MessageNotificationPreferences.read('owner');
    expect(preferences.notifyWhenClosed, isTrue);
    expect(preferences.closedPreview, MessageNotificationPreview.detail);
    expect(preferences.quickReply, isTrue);
  });

  test('settings writes survive reload and drive the runtime preferences',
      () async {
    final store = _store();
    store.updateNotifications(
        closed: false, closedPreview: 'none', notificationQuickReply: false);
    await _reload();
    expect(SpUtil().getDynamic('99chat_settings_owner_notify_when_closed'),
        isFalse);
    expect(SpUtil().getDynamic('99chat_settings_owner_notify_closed_preview'),
        'none');
    expect(SpUtil().getDynamic('99chat_settings_owner_notify_quick_reply'),
        isFalse);
    final restored = _store();
    expect(restored.notifyWhenClosed, isFalse);
    expect(restored.closedNotificationPreview, 'none');
    expect(restored.notificationQuickReply, isFalse);
    expect(restored.quickAnswer, isTrue);
    final runtime = MessageNotificationPreferences.read('owner');
    expect(runtime.notifyWhenClosed, isFalse);
    expect(runtime.closedPreview, MessageNotificationPreview.none);
    expect(runtime.quickReply, isFalse);
    store.updateNotifications(
        closed: true, closedPreview: 'detail', notificationQuickReply: true);
    await _reload();
    expect(_store().notifyWhenClosed, isTrue);
    expect(MessageNotificationPreferences.read('owner').quickReply, isTrue);
    expect(MessageNotificationPreferences.read('owner').closedPreview,
        MessageNotificationPreview.detail);
  });

  for (final preview in ['detail', 'sender', 'none']) {
    test('closed preview $preview persists through store reconstruction',
        () async {
      _store().updateNotifications(closedPreview: preview);
      await _reload();
      expect(_store().closedNotificationPreview, preview);
      expect(MessageNotificationPreferences.read('owner').closedPreview.name,
          preview);
    });
  }

  test('settings are isolated when logging into another account and back',
      () async {
    _store().updateNotifications(
        closed: false, closedPreview: 'none', notificationQuickReply: false);
    await _reload();
    await _login('other');
    final other = _store();
    expect(other.notifyWhenClosed, isTrue);
    expect(other.closedNotificationPreview, 'detail');
    expect(other.notificationQuickReply, isTrue);
    other.updateNotifications(
        closed: true, closedPreview: 'sender', notificationQuickReply: true);
    await _reload();
    await _login('owner');
    final restoredOwner = _store();
    expect(restoredOwner.notifyWhenClosed, isFalse);
    expect(restoredOwner.closedNotificationPreview, 'none');
    expect(restoredOwner.notificationQuickReply, isFalse);
    expect(MessageNotificationPreferences.read('owner').closedPreview,
        MessageNotificationPreview.none);
    expect(MessageNotificationPreferences.read('other').closedPreview,
        MessageNotificationPreview.sender);
    expect(MessageNotificationPreferences.read('other').quickReply, isTrue);
  });

  test(
      'editing text replies preserves the pre-existing voice/video quick answer',
      () async {
    await SpUtil().putBool('99chat_settings_owner_notify_quick_answer', false);
    final store = _store();
    expect(store.quickAnswer, isFalse);
    store.updateNotifications(notificationQuickReply: false);
    await _reload();
    expect(_store().quickAnswer, isFalse);
    store.updateNotifications(notificationQuickReply: true);
    await _reload();
    expect(_store().quickAnswer, isFalse);
    expect(_store().notificationQuickReply, isTrue);
    expect(SpUtil().getDynamic('99chat_settings_owner_notify_quick_answer'),
        isFalse);
  });

  test('editing voice/video quick answer does not overwrite text reply choice',
      () async {
    _store().updateNotifications(notificationQuickReply: false);
    await _reload();
    final store = _store();
    store.updateNotifications(quickAnswer: false);
    await _reload();
    expect(_store().notificationQuickReply, isFalse);
    store.updateNotifications(quickAnswer: true);
    await _reload();
    expect(_store().quickAnswer, isTrue);
    expect(_store().notificationQuickReply, isFalse);
    expect(MessageNotificationPreferences.read('owner').quickReply, isFalse);
  });

  test('message preview changes emit fresh account preferences synchronously',
      () {
    final store = _store();
    final events = <(String, MessageNotificationPreview)>[];
    final subscription = MessageNotificationPreferences.changes.listen((owner) {
      events.add(
          (owner, MessageNotificationPreferences.read(owner).openedPreview));
    });
    addTearDown(subscription.cancel);
    store.updateNotifications(openedPreview: 'none');
    // No pump or microtask flush: native work must be invalidated immediately,
    // and event observers must already see the persisted cache's new value.
    expect(events, [('owner', MessageNotificationPreview.none)]);
    store.updateNotifications(
      quickAnswer: false,
      callClosed: false,
      callRingtoneEnabled: false,
      callRingtone: 'legacy-call-tone',
    );
    expect(events, [('owner', MessageNotificationPreview.none)]);
    expect(store.quickAnswer, isFalse);
    expect(store.callNotifyWhenClosed, isFalse);
    expect(store.callRingtoneEnabled, isFalse);
    expect(store.callRingtone, 'legacy-call-tone');
  });

  test(
      'removing login credentials preserves account-local notification choices',
      () async {
    _store().updateNotifications(
        closed: false, closedPreview: 'sender', notificationQuickReply: false);
    await _reload();
    await DataSp.removeLoginCertificate();
    expect(DataSp.userID, isNull);
    await _login('owner');
    final restored = _store();
    expect(restored.notifyWhenClosed, isFalse);
    expect(restored.closedNotificationPreview, 'sender');
    expect(restored.notificationQuickReply, isFalse);
  });

  test('late writes from the old settings page cannot change the next account',
      () async {
    final old = _store();
    expect(old.ownerUserId, 'owner');
    old.updateNotifications(messageSound: 'soft');
    await _login('other');
    expect(old.isCurrentAccount, isFalse);
    old.updateNotifications(
        opened: false, closed: false, messageSound: 'chime');
    await _reload();
    expect(_store().notifyWhenOpen, isTrue);
    expect(_store().notifyWhenClosed, isTrue);
    expect(_store().messageSound, 'preview000');
    expect(MessageNotificationPreferences.read('owner').messageSound, 'soft');
    expect(SpUtil().getDynamic('99chat_settings_other_message_sound'), isNull);
  });

  test('disposed stores ignore notification writes without throwing', () async {
    final store = SettingsDraftStore();
    store.dispose();
    expect(store.isCurrentAccount, isFalse);
    store.updateNotifications(closed: false, messageSound: 'chime');
    await _reload();
    expect(
        MessageNotificationPreferences.read('owner').notifyWhenClosed, isTrue);
  });

  test('selected sound is normalized, persisted and emitted before returning',
      () async {
    final store = _store();
    final sounds = <String>[];
    final subscription = MessageNotificationPreferences.changes.listen((owner) {
      sounds.add(MessageNotificationPreferences.read(owner).messageSound);
    });
    addTearDown(subscription.cancel);
    store.updateNotifications(messageSound: 'chime');
    expect(sounds, ['chime']);
    await _reload();
    expect(_store().messageSound, 'chime');
    store.updateNotifications(messageSound: '../untrusted.wav');
    expect(sounds.last, MessageNotificationSoundIds.defaultId);
    await _reload();
    expect(_store().messageSound, MessageNotificationSoundIds.defaultId);
  });
}

SettingsDraftStore _store() {
  final store = SettingsDraftStore();
  addTearDown(store.dispose);
  return store;
}

Future<void> _login(String accountID) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': accountID,
    'chatToken': 'fake-chat-token',
    'imToken': 'fake-im-token',
  }));
}

Future<void> _reload() async {
  // Store writes start immediately; let their mocked platform futures finish,
  // then discard the preferences cache before constructing the next store.
  await Future<void>.delayed(Duration.zero);
  await SpUtil().reload();
}
