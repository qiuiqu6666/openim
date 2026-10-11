import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/agent/identity/agent_avatar_directory.dart';
import '../../mark_six_fixtures.dart';

void main() {
  test('avatars are batched, deduplicated and matched by IM ID, not order',
      () async {
    final calls = <List<String>>[];
    final directory = AgentAvatarDirectory(markSixContext(MarkSixFakeApi()),
        loadUsers: (ids) async {
      calls.add(ids);
      return [
        for (final id in ids.reversed)
          PublicUserInfo(userID: id, faceURL: ' https://avatar.test/$id.png '),
        PublicUserInfo(
            userID: 'other', faceURL: 'https://avatar.test/wrong.png'),
      ];
    });
    addTearDown(directory.dispose);
    final results = await Future.wait([
      for (var i = 0; i < 61; i++) directory.resolve('im_$i'),
      directory.resolve(' im_0 '),
    ]);
    expect(calls.map((ids) => ids.length), [50, 11]);
    expect(results.first, 'https://avatar.test/im_0.png');
    expect(results[60], 'https://avatar.test/im_60.png');
    expect(results.last, results.first);
    expect(directory.peek('other'), isNull);
    await directory.resolve('im_0');
    expect(calls, hasLength(2));
  });

  for (final boundary in ['logout', 'permissions', 'dispose']) {
    test('$boundary discards a late SDK result', () async {
      var session = true, capabilities = true;
      final pending = Completer<List<PublicUserInfo>>();
      final directory = AgentAvatarDirectory(
        markSixContext(MarkSixFakeApi(),
            sessionCurrent: () => session,
            capabilitiesCurrent: () => capabilities),
        loadUsers: (_) => pending.future,
      );
      addTearDown(directory.dispose);
      final result = directory.resolve('im_1');
      await Future<void>.delayed(Duration.zero);
      switch (boundary) {
        case 'logout':
          session = false;
        case 'permissions':
          capabilities = false;
        case 'dispose':
          directory.dispose();
      }
      pending.complete([PublicUserInfo(userID: 'im_1', faceURL: 'old-photo')]);
      expect(await result, isNull);
      expect(directory.peek('im_1'), isNull);
      expect(await directory.resolve('im_2'), isNull);
    });
  }

  test('optional lookup failure does not throw or retry on every rebuild',
      () async {
    var calls = 0;
    final directory = AgentAvatarDirectory(markSixContext(MarkSixFakeApi()),
        loadUsers: (_) async {
      calls++;
      throw StateError('SDK unavailable');
    });
    addTearDown(directory.dispose);
    expect(await directory.resolve('im_1'), isNull);
    expect(await directory.resolve('im_1'), isNull);
    expect(calls, 1);
    expect(await directory.resolve(' '), isNull);
    expect(calls, 1);
  });
}
