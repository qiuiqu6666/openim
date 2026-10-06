import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/calling/preferences/call_notification_preference_binding.dart';
import 'package:openim/pages/chat/calling/preferences/call_notification_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      '99chat_settings_alice_notify_quick_answer': false,
      '99chat_settings_alice_call_ringtone_enabled': false,
      '99chat_settings_bob_notify_quick_answer': true,
      '99chat_settings_bob_call_ringtone_enabled': true,
      // A message vibration/sound choice must never mute a phone ringtone.
      '99chat_settings_bob_vibration': false,
      '99chat_settings_bob_message_sound_enabled': false,
    });
    await SpUtil().init();
  });

  test('call delivery reads only the invitation account and call choices', () {
    final alice = CallNotificationPreferences.read(' alice ');
    expect(alice.quickAnswerPopup, isFalse);
    expect(alice.ringtoneEnabled, isFalse);
    final bob = CallNotificationPreferences.read('bob');
    expect(bob.quickAnswerPopup, isTrue);
    expect(bob.ringtoneEnabled, isTrue);
    final freshAccount = CallNotificationPreferences.read('new-account');
    expect(freshAccount.quickAnswerPopup, isTrue);
    expect(freshAccount.ringtoneEnabled, isTrue);
  });

  test('a change applies once to its controller and follows account switches',
      () async {
    var account = 'alice';
    final applied = <bool>[];
    final binding = CallNotificationPreferenceBinding(
      currentAccount: () => account,
      refresh: () => applied
          .add(CallNotificationPreferences.read(account).ringtoneEnabled),
    );
    addTearDown(binding.close);
    binding.attach();
    binding.attach();
    CallNotificationPreferences.notifyChanged('bob');
    expect(applied, isEmpty);
    await SpUtil().putBool('99chat_settings_alice_call_ringtone_enabled', true);
    CallNotificationPreferences.notifyChanged('alice');
    expect(applied, [true]);
    account = 'bob';
    CallNotificationPreferences.notifyChanged('alice');
    await SpUtil().putBool('99chat_settings_bob_call_ringtone_enabled', false);
    CallNotificationPreferences.notifyChanged(' bob ');
    expect(applied, [true, false]);
  });

  test('closing one controller cannot detach or invoke its replacement', () {
    var oldUpdates = 0;
    var replacementUpdates = 0;
    final old = CallNotificationPreferenceBinding(
        currentAccount: () => 'alice', refresh: () => oldUpdates++);
    final replacement = CallNotificationPreferenceBinding(
        currentAccount: () => 'alice', refresh: () => replacementUpdates++);
    addTearDown(replacement.close);
    old.attach();
    replacement.attach();
    old.close();
    old.close();
    old.attach();
    CallNotificationPreferences.notifyChanged('alice');
    expect(oldUpdates, 0);
    expect(replacementUpdates, 1);
  });

  test('logout ignores anonymous changes and invalid storage uses defaults',
      () async {
    var account = '';
    var updates = 0;
    final binding = CallNotificationPreferenceBinding(
        currentAccount: () => account, refresh: () => updates++);
    addTearDown(binding.close);
    binding.attach();
    CallNotificationPreferences.notifyChanged('');
    CallNotificationPreferences.notifyChanged('alice');
    expect(updates, 0);
    account = 'corrupt-account';
    await SpUtil().putString(
        '99chat_settings_corrupt-account_notify_quick_answer', 'false');
    await SpUtil()
        .putInt('99chat_settings_corrupt-account_call_ringtone_enabled', 0);
    final choices = CallNotificationPreferences.read(account);
    expect(choices.quickAnswerPopup, isTrue);
    expect(choices.ringtoneEnabled, isTrue);
  });
}
