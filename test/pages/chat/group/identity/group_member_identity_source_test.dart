import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity.dart';
import 'package:openim_common/openim_common.dart';

class _Fixture {
  String userID = 'im_owner';
  String sdkUserID = 'im_owner';
  String token = 'im_test_token';
  String server = 'https://im.example/prefix/';
  dynamic response = {
    'members': [
      {'groupID': 'g', 'userID': 'im_target', 'account': '0012345678'},
      {'groupID': 'g', 'userID': 'im_restricted'},
    ],
  };
  final authFailures = <int>[];
  final requests = <(String, Map<String, dynamic>, Options)>[];
  late final source = GroupMemberIdentitySource(
    currentUserID: () => userID,
    currentToken: () => token,
    sdkUserID: () => sdkUserID,
    baseURL: () => server,
    onAuthFailure: authFailures.add,
    poster: (url, data, options) async {
      requests.add((url, data, options));
      return await response;
    },
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter({this.pendingResponse});

  final Future<Map<String, dynamic>>? pendingResponse;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(await pendingResponse ??
          {
            'errCode': 0,
            'data': {
              'members': [
                {'groupID': 'g', 'userID': 'im_raw', 'account': '0012345678'},
              ],
            },
          }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('list uses the IM endpoint, JSON and a fresh operation ID', () async {
    final fixture = _Fixture();
    final members = await fixture.source.list(
      groupID: 'g',
      pageNumber: 3,
      showNumber: 50,
      filter: 5,
      keyword: 'Alice',
    );
    await fixture.source.list(groupID: 'g');
    final first = fixture.requests.first;
    expect(first.$1, 'https://im.example/prefix/group/get_group_member_list');
    expect(first.$2, {
      'groupID': 'g',
      'pagination': {'pageNumber': 3, 'showNumber': 50},
      'filter': 5,
      'keyword': 'Alice',
    });
    expect(first.$3.contentType, Headers.jsonContentType);
    expect(first.$3.headers?['token'], 'im_test_token');
    expect(first.$3.headers?['operationID'], isNotEmpty);
    expect(first.$3.headers?['operationID'],
        isNot(fixture.requests.last.$3.headers?['operationID']));
    expect(
        members.map((member) => member.userID), ['im_target', 'im_restricted']);
    expect(members.first.account, '0012345678');
    expect(members.last.account, isNull);
  });

  test('members sends original IM IDs without a general profile request',
      () async {
    final fixture = _Fixture();
    await fixture.source.members(
      groupID: 'g',
      userIDList: ['im_target', '2138014845'],
    );
    expect(fixture.requests.single.$1,
        'https://im.example/prefix/group/get_group_members_info');
    expect(fixture.requests.single.$2, {
      'groupID': 'g',
      'userIDs': ['im_target', '2138014845'],
    });
  });

  test('incremental request and response preserve accounts for insert/update',
      () async {
    final fixture = _Fixture()
      ..response = {
        'versionID': 'v-next',
        'version': 12,
        'insert': [
          {'groupID': 'g', 'userID': 'im_insert', 'account': '0012345678'},
        ],
        'update': [
          {'groupID': 'g', 'userID': 'im_update'},
        ],
        'delete': ['im_deleted'],
      };
    final result = await fixture.source
        .incremental(groupID: 'g', versionID: 'v-old', version: 11);
    expect(fixture.requests.single.$1,
        'https://im.example/prefix/group/get_incremental_group_members');
    expect(fixture.requests.single.$2,
        {'groupID': 'g', 'versionID': 'v-old', 'version': 11});
    expect(result.insert.single.account, '0012345678');
    expect(result.update.single.account, isNull);
    expect(result.delete, ['im_deleted']);
  });

  test('batch sends current IM userID and parses group-keyed respList',
      () async {
    final fixture = _Fixture()
      ..response = {
        'respList': {
          'g': {
            'versionID': 'v-next',
            'version': 12,
            'update': [
              {'groupID': 'g', 'userID': 'im_update', 'account': '0012345678'},
            ],
          },
          'restricted': {
            'insert': [
              {'groupID': 'restricted', 'userID': 'im_hidden'},
            ],
          },
        },
      };
    final result = await fixture.source.batch(reqList: const [
      GroupMemberIdentityVersion(groupID: 'g', versionID: 'v-old', version: 11),
      GroupMemberIdentityVersion(groupID: 'restricted'),
    ]);
    expect(fixture.requests.single.$1,
        'https://im.example/prefix/group/get_incremental_group_members_batch');
    expect(fixture.requests.single.$2, {
      'userID': 'im_owner',
      'reqList': [
        {'groupID': 'g', 'versionID': 'v-old', 'version': 11},
        {'groupID': 'restricted', 'versionID': '', 'version': 0},
      ],
    });
    expect(result['g']?.update.single.account, '0012345678');
    expect(result['restricted']?.insert.single.account, isNull);
  });

  for (final change in ['userID', 'token', 'server', 'sdkUserID']) {
    test('late response is discarded after $change changes', () async {
      final pendingResponse = Completer<dynamic>();
      final fixture = _Fixture()..response = pendingResponse.future;
      final request = fixture.source.list(groupID: 'g');
      switch (change) {
        case 'userID':
          fixture.userID = 'im_other';
        case 'token':
          fixture.token = 'other-token';
        case 'server':
          fixture.server = 'https://other.example';
        case 'sdkUserID':
          fixture.sdkUserID = 'im_other_sdk';
      }
      final assertion = expectLater(
          request, throwsA(isA<GroupMemberIdentitySessionChanged>()));
      pendingResponse.complete({
        'members': [
          {'userID': 'im_target', 'account': '0012345678'},
        ],
      });
      await assertion;
    });
  }

  test('late transport errors are also scoped to their old session', () async {
    final pendingResponse = Completer<dynamic>();
    final fixture = _Fixture()..response = pendingResponse.future;
    final request =
        fixture.source.members(groupID: 'g', userIDList: ['im_target']);
    fixture.userID = 'im_other';
    final assertion =
        expectLater(request, throwsA(isA<GroupMemberIdentitySessionChanged>()));
    pendingResponse.completeError((1506, 'old token expired'));
    await assertion;
  });

  test('current server errors propagate without another identity lookup',
      () async {
    final fixture = _Fixture()
      ..response = {
        'errCode': 1006,
        'errMsg': 'denied',
        'errDlt': 'not in group'
      };
    await expectLater(fixture.source.list(groupID: 'g'),
        throwsA(equals((1006, 'not in group'))));
    expect(fixture.requests, hasLength(1));
  });

  test('empty ID sets do not send a request', () async {
    final fixture = _Fixture();
    expect(await fixture.source.members(groupID: 'g', userIDList: []), isEmpty);
    expect(await fixture.source.batch(reqList: []), isEmpty);
    expect(fixture.requests, isEmpty);
  });

  test('empty session and invalid arguments fail before transport', () async {
    final fixture = _Fixture()..token = '';
    await expectLater(fixture.source.list(groupID: 'g'), throwsStateError);
    await expectLater(fixture.source.list(groupID: ''), throwsArgumentError);
    await expectLater(
        fixture.source.list(groupID: 'g', pageNumber: 0), throwsArgumentError);
    await expectLater(fixture.source.members(groupID: 'g', userIDList: ['']),
        throwsArgumentError);
    await expectLater(fixture.source.incremental(groupID: 'g', version: -1),
        throwsArgumentError);
    expect(fixture.requests, isEmpty);
  });

  test(
      'default HTTP transport preserves extra account in the raw JSON envelope',
      () async {
    final adapter = _Adapter();
    final client = Dio()..httpClientAdapter = adapter;
    addTearDown(() => client.close());
    final source = GroupMemberIdentitySource(
      client: client,
      onAuthFailure: (_) {},
      currentUserID: () => 'im_owner',
      currentToken: () => 'im_token',
      sdkUserID: () => 'im_owner',
      baseURL: () => 'https://im.example',
    );
    final result = await source.members(groupID: 'g', userIDList: ['im_raw']);
    expect(adapter.request?.uri.toString(),
        'https://im.example/group/get_group_members_info');
    expect(adapter.request?.headers['token'], 'im_token');
    expect(adapter.request?.headers['operationID'], isNotEmpty);
    expect(adapter.request?.contentType, Headers.jsonContentType);
    expect(result.single.userID, 'im_raw');
    expect(result.single.account, '0012345678');
  });

  for (final code in [1506, 20101]) {
    test('current $code triggers auth feedback once after guarding', () async {
      final fixture = _Fixture()
        ..response = {'errCode': code, 'errMsg': 'expired'};
      await expectLater(fixture.source.list(groupID: 'g'),
          throwsA(equals((code, 'expired'))));
      expect(fixture.authFailures, [code]);
    });

    for (final change in ['userID', 'token', 'server', 'sdkUserID']) {
      test('stale $change $code never triggers auth feedback', () async {
        final pendingResponse = Completer<dynamic>();
        final fixture = _Fixture()..response = pendingResponse.future;
        final request = fixture.source.list(groupID: 'g');
        switch (change) {
          case 'userID':
            fixture.userID = 'im_other';
          case 'token':
            fixture.token = 'other-token';
          case 'server':
            fixture.server = 'https://other.example';
          case 'sdkUserID':
            fixture.sdkUserID = 'im_other_sdk';
        }
        final assertion = expectLater(
            request, throwsA(isA<GroupMemberIdentitySessionChanged>()));
        pendingResponse.complete({'errCode': code, 'errMsg': 'expired'});
        await assertion;
        expect(fixture.authFailures, isEmpty);
      });
    }
  }

  test('HTTP transport skips shared interceptors before stale auth guard',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    final adapter = _Adapter(pendingResponse: pending.future);
    final client = Dio()..httpClientAdapter = adapter;
    var sharedResponses = 0;
    final interceptor = InterceptorsWrapper(onResponse: (response, handler) {
      sharedResponses++;
      handler.next(response);
    });
    dio.interceptors.add(interceptor);
    addTearDown(() {
      dio.interceptors.remove(interceptor);
      client.close();
    });
    var sdkID = 'im_owner';
    var server = 'https://im.example';
    final authFailures = <int>[];
    final source = GroupMemberIdentitySource(
      client: client,
      onAuthFailure: authFailures.add,
      currentUserID: () => 'im_owner',
      currentToken: () => 'im_token',
      sdkUserID: () => sdkID,
      baseURL: () => server,
    );
    final request = source.list(groupID: 'g');
    sdkID = 'im_other';
    server = 'https://other.example';
    final assertion =
        expectLater(request, throwsA(isA<GroupMemberIdentitySessionChanged>()));
    pending.complete({'errCode': 1506, 'errMsg': 'expired'});
    await assertion;
    expect(sharedResponses, 0);
    expect(authFailures, isEmpty);
  });

  test('list only accepts members belonging to the requested group', () async {
    final fixture = _Fixture()
      ..response = {
        'members': [
          {'groupID': 'g', 'userID': 'im_member', 'account': '0012345678'},
          {'groupID': 'other', 'userID': 'im_other', 'account': '9999999999'},
          {'userID': 'im_missing_group', 'account': '8888888888'},
          {'groupID': 'g', 'userID': '', 'account': '7777777777'},
        ],
      };
    final members = await fixture.source.list(groupID: 'g');
    expect(members.map((member) => member.userID), ['im_member']);
    expect(members.single.account, '0012345678');
  });

  test('members also rejects unrequested user IDs in the same group', () async {
    final fixture = _Fixture()
      ..response = {
        'members': [
          {'groupID': 'g', 'userID': 'im_member', 'account': '0012345678'},
          {'groupID': 'g', 'userID': 'im_extra', 'account': '9999999999'},
          {'groupID': 'other', 'userID': 'im_member', 'account': '8888888888'},
        ],
      };
    final members =
        await fixture.source.members(groupID: 'g', userIDList: ['im_member']);
    expect(members.map((member) => member.userID), ['im_member']);
  });

  test('member request ownership uses the ID set captured before await',
      () async {
    final pendingResponse = Completer<dynamic>();
    final fixture = _Fixture()..response = pendingResponse.future;
    final ids = ['im_member'];
    final request = fixture.source.members(groupID: 'g', userIDList: ids);
    ids[0] = 'im_extra';
    pendingResponse.complete({
      'members': [
        {'groupID': 'g', 'userID': 'im_member', 'account': '0012345678'},
        {'groupID': 'g', 'userID': 'im_extra', 'account': '9999999999'},
      ],
    });
    expect((await request).map((member) => member.userID), ['im_member']);
    expect(fixture.requests.single.$2['userIDs'], ['im_member']);
  });

  test('incremental insert and update reject unrelated group accounts',
      () async {
    final fixture = _Fixture()
      ..response = {
        'insert': [
          {'groupID': 'g', 'userID': 'im_insert', 'account': '0012345678'},
          {'groupID': 'other', 'userID': 'im_alien', 'account': '9999999999'},
        ],
        'update': [
          {'groupID': 'g', 'userID': 'im_update'},
          {'userID': 'im_unscoped', 'account': '8888888888'},
        ],
      };
    final result = await fixture.source.incremental(groupID: 'g');
    expect(result.insert.map((member) => member.userID), ['im_insert']);
    expect(result.update.map((member) => member.userID), ['im_update']);
    fixture.response = {
      'group': {'groupID': 'other'}
    };
    await expectLater(
        fixture.source.incremental(groupID: 'g'), throwsFormatException);
  });

  test('batch excludes unrequested groups and mismatched nested members',
      () async {
    final fixture = _Fixture()
      ..response = {
        'respList': {
          'g': {
            'insert': [
              {'groupID': 'g', 'userID': 'im_member', 'account': '0012345678'},
              {
                'groupID': 'other',
                'userID': 'im_other',
                'account': '9999999999'
              },
            ],
          },
          'other': {
            'insert': [
              {
                'groupID': 'other',
                'userID': 'im_other',
                'account': '9999999999'
              },
            ],
          },
        },
      };
    final results = await fixture.source
        .batch(reqList: const [GroupMemberIdentityVersion(groupID: 'g')]);
    expect(results.keys, ['g']);
    expect(results['g']?.insert.single.userID, 'im_member');
  });
}
