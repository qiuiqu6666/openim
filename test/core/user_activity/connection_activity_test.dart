import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/user_activity/activity_collector.dart';
import 'package:openim/core/user_activity/connection_activity.dart';

void main() {
  const first =
      (accountID: 'first', token: 'one', endpoint: 'https://chat.invalid');
  const second =
      (accountID: 'second', token: 'two', endpoint: 'https://chat.invalid');

  test('initial/repeated connections do not become reconnects', () {
    final c = ConnectionActivity()..begin(first);
    c.lost();
    c.lost();
    c.connected();
    c.connected();
    expect(c.take(first), isEmpty);
    c.lost();
    c.lost();
    c.connected();
    c.connected();
    expect(c.take(first), ['connection_lost', 'reconnect']);
    expect(c.take(first), isEmpty);
  });

  for (final restoreBeforeConnect in [true, false]) {
    test('restoring saved credentials reports once ($restoreBeforeConnect)',
        () {
      final c = ConnectionActivity()..begin(first);
      if (restoreBeforeConnect) c.restored();
      c.connected();
      c.restored();
      c.restored();
      expect(c.take(first), ['session_restore']);
      c.connected();
      expect(c.take(first), isEmpty);
    });
  }

  test('logout/account switch cannot attribute old transitions to new user',
      () {
    final c = ConnectionActivity()
      ..begin(first)
      ..connected()
      ..lost();
    expect(c.take(second), isEmpty);
    c.reset();
    c.connected();
    expect(c.take(first), isEmpty);
    c.begin(second);
    c.connected();
    expect(c.take(second), isEmpty);
  });

  test('connection reporting uses dedicated kind and existing bounded upload',
      () async {
    final batches = <Map<String, Object>>[];
    var id = 0;
    final collector = ActivityCollector(
      newID: () => 'connection-${++id}',
      upload: (_, batch) async {
        batches.add(batch);
        return true;
      },
    )..bind(first);
    await collector.flush();
    collector.connection('reconnect');
    collector.connection('login');
    await collector.flush();
    final events = batches.last['events'] as List;
    expect(events, hasLength(1));
    expect(events.single['kind'], 'connection');
    expect(events.single['action'], 'reconnect');
    expect(events.single.containsKey('result'), isFalse);
  });
}
