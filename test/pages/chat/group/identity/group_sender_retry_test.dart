import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_sender_avatars.dart';

// Recovery must retry without requiring a new UI or connection event.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('failed sender refresh automatically converges', () async {
    var online = false;
    var calls = 0;
    final names = GroupSenderAvatars(
        isCurrent: () => true,
        retryDelay: const Duration(milliseconds: 10),
        lookup: (ids) async {
          calls++;
          if (!online) throw StateError('temporary profile failure');
          return [GroupMembersInfo(userID: 'peer', nickname: 'current-name')];
        });
    addTearDown(names.close);
    final message =
        Message(sendID: 'peer', senderNickname: 'old-snapshot', sendTime: 1);
    names.refreshMessages([message]);
    // Mark the initially loaded sender too, as normal message binding does.
    names.sync([message]);
    await Future<void>.delayed(Duration.zero);
    online = true;
    names.sync([message]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(names.nicknameFor(message), 'old-snapshot');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls, 2);
    expect(names.nicknameFor(message), 'current-name');
  });

  testWidgets('sender retries are bounded and close cancels pending work',
      (tester) async {
    var calls = 0;
    final names = GroupSenderAvatars(
        isCurrent: () => true,
        lookup: (_) async {
          calls++;
          throw StateError('offline');
        });
    final message = Message(sendID: 'peer', senderNickname: 'snapshot');
    names.sync([message]);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(calls, 4); // Initial request plus three delayed retries.
    expect(names.nicknameFor(message), 'snapshot');
    names.refreshMessages([message]);
    await tester.pump();
    expect(calls, 5);
    names.close();
    await tester.pump(const Duration(seconds: 20));
    expect(calls, 5);
  });

  testWidgets('fallback profile lookup retries without another event',
      (tester) async {
    var calls = 0;
    final names = GroupSenderAvatars(
      isCurrent: () => true,
      lookup: (_) async => [],
      lookupProfiles: (_) async {
        calls++;
        if (calls == 1) throw StateError('temporary profile outage');
        return [GroupMembersInfo(userID: 'peer', nickname: 'latest')];
      },
    );
    final message = Message(sendID: 'peer', senderNickname: 'snapshot');
    names.sync([message]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 2);
    expect(names.nicknameFor(message), 'latest');
    names.close();
  });
}
