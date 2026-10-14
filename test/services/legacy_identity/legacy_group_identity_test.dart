import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/legacy_identity/legacy_group_identity.dart';
import 'package:openim/services/legacy_identity/legacy_server_snapshot.dart';

void main() {
  const group = 'lg_4b41122c9b36f283ffa962265a4385a6';
  for (final server in [
    'http://129.226.192.93:10002',
    'https://99imapi.99chat.vip',
    'https://99imapi.99chat.vip/',
    'https://99imapi.99chat.vip:443',
  ]) {
    test('migrated group identity follows its deployment: $server', () {
      expect(LegacyGroupIdentity.canonical(group, server: server), '@$group');
      expect(
          LegacyGroupIdentity.canonical('@$group', server: server), '@$group');
      expect(
          LegacyGroupIdentity.canonical('regular', server: server), 'regular');
    });
  }
  for (final server in [
    'https://another.example',
    'https://99imapi.99chat.vip.attacker.example',
    'https://user@99imapi.99chat.vip',
    'http://99imapi.99chat.vip',
    'https://99imapi.99chat.vip:8443',
    'https://99imapi.99chat.vip/other',
    'https://99imapi.99chat.vip?next=other',
    'https://99imapi.99chat.vip#other',
  ]) {
    test('unrelated or malformed route does not alias IDs: $server', () {
      expect(LegacyGroupIdentity.canonical(group, server: server), group);
    });
  }
  test('recognizing the current domain grants no destructive cleanup access',
      () {
    expect(LegacyServerSnapshot.allowedServer('https://99imapi.99chat.vip'),
        isFalse);
  });
}
