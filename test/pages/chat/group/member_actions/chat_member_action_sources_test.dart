import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_result.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_sources.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late ChatMemberActionSources sources;
  late List<MethodCall> calls;

  void mock(Future<Object?> Function(MethodCall) handle) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return handle(call);
    });
  }

  setUp(() {
    sources = ChatMemberActionSources.sdk();
    calls = [];
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('SDK snapshot queries both participants and filters by group identity',
      () async {
    mock((call) async => switch (call.method) {
          'getGroupsInfo' => jsonEncode([
              {'groupID': 'another-group', 'ownerUserID': 'unrelated-owner'},
              {
                'groupID': 'group',
                'ownerUserID': 'self',
                'status': 0,
                'groupType': GroupType.work,
              },
            ]),
          'getGroupMembersInfo' => jsonEncode([
              {
                'groupID': 'another-group',
                'userID': 'self',
                'roleLevel': GroupRoleLevel.member,
              },
              {
                'groupID': 'another-group',
                'userID': 'target',
                'roleLevel': GroupRoleLevel.owner,
              },
              {
                'groupID': 'group',
                'userID': 'unrequested',
                'roleLevel': GroupRoleLevel.member,
              },
              {
                'groupID': 'group',
                'userID': 'target',
                'roleLevel': GroupRoleLevel.member,
                'muteEndTime': 1234,
              },
              {
                'groupID': 'group',
                'userID': 'self',
                'roleLevel': GroupRoleLevel.owner,
              },
            ]),
          'isJoinGroup' => 'true',
          _ => throw StateError('Unexpected SDK call: ${call.method}'),
        });

    final snapshot = await sources.read('group', 'self', 'target');

    expect(snapshot.group?.groupID, 'group');
    expect(snapshot.group?.ownerUserID, 'self');
    expect(snapshot.self?.userID, 'self');
    expect(snapshot.self?.roleLevel, GroupRoleLevel.owner);
    expect(snapshot.target?.userID, 'target');
    expect(snapshot.target?.roleLevel, GroupRoleLevel.member);
    expect(snapshot.target?.muteEndTime, 1234);
    expect(snapshot.isJoined, isTrue);
    expect(
        calls.map((call) => call.method),
        unorderedEquals([
          'getGroupsInfo',
          'getGroupMembersInfo',
          'isJoinGroup',
        ]));
    expect(
        calls
            .singleWhere((call) => call.method == 'getGroupsInfo')
            .arguments['groupIDList'],
        ['group']);
    final members =
        calls.singleWhere((call) => call.method == 'getGroupMembersInfo');
    expect(members.arguments['groupID'], 'group');
    expect(members.arguments['userIDList'], ['self', 'target']);
    expect(
        calls
            .singleWhere((call) => call.method == 'isJoinGroup')
            .arguments['groupID'],
        'group');
    for (final call in calls) {
      expect(call.arguments['ManagerName'], 'groupManager');
    }
  });

  test('missing target never adopts same user from another group', () async {
    mock((call) async => switch (call.method) {
          'getGroupsInfo' => jsonEncode([
              {'groupID': 'group', 'ownerUserID': 'self'},
            ]),
          'getGroupMembersInfo' => jsonEncode([
              {
                'groupID': 'group',
                'userID': 'self',
                'roleLevel': GroupRoleLevel.owner,
              },
              {
                'groupID': 'another-group',
                'userID': 'target',
                'roleLevel': GroupRoleLevel.member,
              },
            ]),
          'isJoinGroup' => 'true',
          _ => throw StateError('Unexpected SDK call: ${call.method}'),
        });

    final snapshot = await sources.read('group', 'self', 'target');

    expect(snapshot.self?.userID, 'self');
    expect(snapshot.target, isNull);
    expect(snapshot.isJoined, isTrue);
  });

  test('missing group and left membership stay unavailable in snapshot',
      () async {
    mock((call) async => switch (call.method) {
          'getGroupsInfo' => jsonEncode([
              {'groupID': 'another-group'},
            ]),
          'getGroupMembersInfo' => jsonEncode([]),
          'isJoinGroup' => 'false',
          _ => throw StateError('Unexpected SDK call: ${call.method}'),
        });

    final snapshot = await sources.read('group', 'self', 'target');

    expect(snapshot.group, isNull);
    expect(snapshot.self, isNull);
    expect(snapshot.target, isNull);
    expect(snapshot.isJoined, isFalse);
  });

  test(
      'snapshot query failure propagates instead of returning partial authority',
      () async {
    mock((call) async {
      if (call.method == 'getGroupMembersInfo') {
        throw PlatformException(code: 'permission-denied');
      }
      return call.method == 'isJoinGroup' ? 'true' : jsonEncode([]);
    });

    await expectLater(
      sources.read('group', 'self', 'target'),
      throwsA(isA<ParallelWaitError>().having(
        (error) => error.errors.$2.error,
        'member query error',
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'permission-denied'),
      )),
    );
  });

  test('SDK mute and unmute send duration seconds and accept null success',
      () async {
    mock((call) async {
      expect(call.method, 'changeGroupMemberMute');
      return null;
    });

    await sources.mute('group', 'target', 3600);
    await sources.mute('group', 'target', 0);

    expect(calls, hasLength(2));
    expect(calls.map((call) => call.arguments['seconds']), [3600, 0]);
    for (final call in calls) {
      expect(call.arguments['groupID'], 'group');
      expect(call.arguments['userID'], 'target');
      expect(call.arguments['ManagerName'], 'groupManager');
    }
  });

  test('SDK kick requests only chosen member and accepts null success',
      () async {
    mock((call) async {
      expect(call.method, 'kickGroupMember');
      return null;
    });

    await sources.remove('group', 'target');

    final request = calls.single;
    expect(request.arguments['groupID'], 'group');
    expect(request.arguments['userIDList'], ['target']);
    expect(request.arguments['reason'], '移除群聊');
    expect(request.arguments['ManagerName'], 'groupManager');
  });

  test('SDK mute, unmute and kick accept the core JSON empty string callback',
      () async {
    mock((call) async => '""');

    await sources.mute('group', 'target', 3600);
    await sources.mute('group', 'target', 0);
    await sources.remove('group', 'target');

    expect(calls.map((call) => call.method), [
      'changeGroupMemberMute',
      'changeGroupMemberMute',
      'kickGroupMember',
    ]);
    expect(calls.take(2).map((call) => call.arguments['seconds']), [3600, 0]);
    expect(calls.last.arguments['userIDList'], ['target']);
  });

  test('SDK mute and kick preserve native channel errors', () async {
    final failure = PlatformException(
        code: '1002', message: 'Permission denied', details: 'native error');
    mock((call) async => throw failure);

    for (final action in [
      () => sources.mute('group', 'target', 3600),
      () => sources.mute('group', 'target', 0),
      () => sources.remove('group', 'target'),
    ]) {
      await expectLater(
        action(),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', '1002')
            .having((error) => error.message, 'message', 'Permission denied')
            .having((error) => error.details, 'details', 'native error')),
      );
    }
    expect(calls, hasLength(3));
  });

  test('SDK kick rejects explicit per-member failure payload', () async {
    mock((call) async {
      expect(call.method, 'kickGroupMember');
      return jsonEncode([
        {'userID': 'target', 'result': 1002, 'errMsg': 'Permission denied'},
      ]);
    });

    await expectLater(
      sources.remove('group', 'target'),
      throwsA(isA<ChatMemberActionResultException>()
          .having((error) => error.targetUserID, 'targetUserID', 'target')
          .having((error) => error.code, 'code', 1002)
          .having((error) => error.message, 'message', 'Permission denied')),
    );
    expect(calls.single.arguments['userIDList'], ['target']);
  });

  test('SDK mute rejects explicit error response', () async {
    mock((call) async {
      expect(call.method, 'changeGroupMemberMute');
      return {'errCode': 1002, 'errMsg': 'Permission denied'};
    });

    await expectLater(
      sources.mute('group', 'target', 3600),
      throwsA(isA<ChatMemberActionResultException>()
          .having((error) => error.targetUserID, 'targetUserID', 'target')
          .having((error) => error.code, 'code', 1002)),
    );
  });
}
