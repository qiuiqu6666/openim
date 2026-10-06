import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/presence/contact_presence_policy.dart';
import 'package:openim/pages/contacts/presence_store.dart';

void main() {
  for (final userID in ['assistant', '99Message', '99Pay']) {
    test('$userID stays available without cache or after an offline update',
        () {
      final cachedOnline = UserPresence(true, null);
      final sdkOffline = UserPresence(false, 123456, showLastSeen: false);
      for (final presence in [null, cachedOnline, sdkOffline]) {
        final displayed = ContactPresencePolicy.resolve(
            userID: userID, ex: '{invalid', presence: presence)!;
        expect(displayed.displayOnline, isTrue);
        expect(displayed.lastSeenAt, isNull);
      }
      expect(sdkOffline.online, isFalse,
          reason: 'The display policy must not rewrite a real SDK snapshot.');
      expect(sdkOffline.lastSeenAt, 123456);
      expect(sdkOffline.showLastSeen, isFalse);
    });
  }

  test('trusted official metadata supplies presence without a known role', () {
    final offline = UserPresence(false, 42);
    for (final ex in [
      '{"accountType":"official"}',
      '{"accountType":"official","officialRole":"message"}',
      '{"accountType":"official","officialRole":"assistant"}',
    ]) {
      final displayed = ContactPresencePolicy.resolve(
          userID: 'server-assigned-account', ex: ex, presence: offline)!;
      expect(displayed.displayOnline, isTrue);
      expect(displayed.lastSeenAt, isNull);
    }
    expect(offline.online, isFalse);
    expect(offline.lastSeenAt, 42);
  });

  test('ordinary missing presence remains unavailable', () {
    for (final userID in [null, '', 'ordinary', '99Pay-copy']) {
      expect(ContactPresencePolicy.resolve(userID: userID), isNull);
    }
    expect(
        ContactPresencePolicy.resolve(
            userID: '', ex: '{"accountType":"official"}'),
        isNull,
        reason: 'Metadata without an account identity cannot grant presence.');
  });

  test('malformed or non-official metadata preserves ordinary snapshots', () {
    final offline = UserPresence(false, 987654);
    for (final ex in [
      null,
      '',
      ' ',
      '{invalid',
      '[]',
      '"official"',
      '{"accountType":true}',
      '{"accountType":["official"]}',
      '{"accountType":"Official"}',
      '{"officialRole":"message"}',
      '{"accountType":"personal"}',
    ]) {
      expect(
          ContactPresencePolicy.resolve(
              userID: 'ordinary', ex: ex, presence: offline),
          same(offline),
          reason: 'Invalid metadata must not upgrade an ordinary account.');
    }
  });

  test('ordinary online and offline snapshots keep their original data', () {
    for (final presence in [
      UserPresence(true, null),
      UserPresence(false, 12)
    ]) {
      expect(
          ContactPresencePolicy.resolve(userID: 'ordinary', presence: presence),
          same(presence));
    }
  });

  test('ordinary hidden last-seen privacy and coarse labels remain intact', () {
    final now = DateTime(2026, 10, 5, 12);
    for (final presence in [
      UserPresence(true, null, showLastSeen: false),
      UserPresence(
          false, now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
          showLastSeen: false),
    ]) {
      final displayed = ContactPresencePolicy.resolve(
          userID: 'ordinary', presence: presence)!;
      expect(displayed, same(presence));
      expect(displayed.hidden, isTrue);
      expect(displayed.displayOnline, isFalse);
      expect(displayed.labelAt(now), presence.labelAt(now));
    }
  });
}
