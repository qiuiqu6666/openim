import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_friend_protection_store.dart';

Map<String, dynamic> _state(bool protect, {bool canManage = true}) => {
      'errCode': 0,
      'data': {'protect': protect, 'canManage': canManage},
    };

class _Fixture {
  _Fixture() {
    client.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      final reply = Completer<Map<String, dynamic>>();
      replies.add(reply);
      try {
        handler.resolve(
            Response(requestOptions: request, data: await reply.future));
      } catch (error) {
        handler.reject(DioException(requestOptions: request, error: error));
      }
    }));
    store = GroupFriendProtectionStore(
      '@group',
      client: client,
      notify: notices.add,
      currentUserID: () => owner,
      sdkUserID: () => sdkOwner,
      currentToken: () => token,
      baseURL: () => server,
    );
  }

  String owner = 'im_owner';
  String sdkOwner = 'im_owner';
  String token = 'chat_token';
  String server = 'https://chat.example/prefix/';
  final client = Dio();
  final notices = <String>[];
  final requests = <RequestOptions>[];
  final replies = <Completer<Map<String, dynamic>>>[];
  late final GroupFriendProtectionStore store;

  Future<void> waitRequests(int count) async {
    for (var attempt = 0; attempt < 20 && requests.length < count; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(requests, hasLength(count));
  }

  Future<void> seed() async {
    final read = store.refresh();
    await waitRequests(1);
    replies[0].complete(_state(true));
    await read;
  }

  void change(String dimension) {
    switch (dimension) {
      case 'owner':
        owner = 'im_other';
      case 'sdkOwner':
        sdkOwner = 'im_other_sdk';
      case 'token':
        token = 'other-token';
      case 'server':
        server = 'https://other.example';
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'me', 'chatToken': 'chat'}));
  });
  test('uses Chat state and reconciles PUT without response data', () async {
    final requests = <RequestOptions>[];
    var protected = false;
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      if (r.method == 'PUT') protected = r.data['protect'] as bool;
      h.resolve(Response(requestOptions: r, data: {
        'errCode': 0,
        if (r.method == 'GET') 'data': {'protect': protected, 'canManage': true}
      }));
    }));
    final store =
        GroupFriendProtectionStore('@group', client: client, notify: (_) {});
    await store.refresh();
    expect(store.ready.value, true);
    await store.setProtected(true);
    expect(requests.map((r) => r.method), ['GET', 'PUT', 'GET']);
    expect(requests[1].data, {'protect': true});
    expect(requests[1].headers['token'], 'chat');
    expect(store.protect.value, true);
    store.dispose();
  });
  test('ordinary member cannot write and read failure invalidates state',
      () async {
    var fail = false;
    final requests = <RequestOptions>[];
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      h.resolve(Response(
          requestOptions: r,
          data: fail
              ? {'errCode': 20020}
              : {
                  'errCode': 0,
                  'data': {'protect': true, 'canManage': false}
                }));
    }));
    final store =
        GroupFriendProtectionStore('group', client: client, notify: (_) {});
    await store.refresh();
    await store.setProtected(false);
    expect(requests.length, 1);
    fail = true;
    await store.refresh();
    expect(store.ready.value, false);
    expect(store.failed.value, true);
    await store.setProtected(false);
    expect(requests.length, 2);
    store.dispose();
  });

  test('request keeps Chat base path, token and unique operation IDs',
      () async {
    final fixture = _Fixture();
    await fixture.seed();
    expect(fixture.requests.single.uri.toString(),
        'https://chat.example/prefix/chat/groups/%40group/friend-protect');
    expect(fixture.requests.single.headers['token'], 'chat_token');
    final next = fixture.store.refresh();
    await fixture.waitRequests(2);
    fixture.replies[1].complete(_state(false));
    await next;
    expect(fixture.requests[0].headers['operationID'],
        isNot(fixture.requests[1].headers['operationID']));
    fixture.store.dispose();
  });

  for (final dimension in ['owner', 'sdkOwner', 'token', 'server']) {
    test('$dimension changes immediately revoke confirmed UI state', () async {
      final fixture = _Fixture();
      await fixture.seed();
      fixture.change(dimension);
      expect(fixture.store.ready.value, isFalse);
      expect(fixture.store.protect.value, isFalse);
      expect(fixture.store.canManage.value, isFalse);
      expect(fixture.store.busy.value, isFalse);
      await fixture.store.refresh();
      await fixture.store.setProtected(false);
      expect(fixture.requests, hasLength(1));
      fixture.store.dispose();
    });

    test('$dimension changes reject a late read response', () async {
      final fixture = _Fixture();
      final read = fixture.store.refresh();
      await fixture.waitRequests(1);
      fixture.change(dimension);
      fixture.replies[0].complete(_state(true));
      await read;
      expect(fixture.store.ready.value, isFalse);
      expect(fixture.store.protect.value, isFalse);
      expect(fixture.store.canManage.value, isFalse);
      expect(fixture.store.failed.value, isFalse);
      expect(fixture.notices, isEmpty);
      fixture.store.dispose();
    });
  }

  test('new refresh replaces a pending read and old success cannot restore it',
      () async {
    final fixture = _Fixture();
    final older = fixture.store.refresh();
    await fixture.waitRequests(1);
    final newer = fixture.store.refresh();
    await fixture.waitRequests(2);
    fixture.replies[1].complete(_state(false, canManage: false));
    await newer;
    fixture.replies[0].complete(_state(true));
    await older;
    expect(fixture.store.ready.value, isTrue);
    expect(fixture.store.protect.value, isFalse);
    expect(fixture.store.canManage.value, isFalse);
    expect(fixture.store.busy.value, isFalse);
    fixture.store.dispose();
  });

  test('old read failure cannot clear newer loading or mark it failed',
      () async {
    final fixture = _Fixture();
    final older = fixture.store.refresh();
    await fixture.waitRequests(1);
    final newer = fixture.store.refresh();
    await fixture.waitRequests(2);
    fixture.replies[0].completeError(TimeoutException('old read'));
    await older;
    expect(fixture.store.busy.value, isTrue);
    expect(fixture.store.failed.value, isFalse);
    fixture.replies[1].complete(_state(true));
    await newer;
    expect(fixture.store.ready.value, isTrue);
    expect(fixture.store.busy.value, isFalse);
    fixture.store.dispose();
  });

  test('writes block concurrent writes and reads until GET reconciliation',
      () async {
    final fixture = _Fixture();
    await fixture.seed();
    final write = fixture.store.setProtected(false);
    await fixture.waitRequests(2);
    await fixture.store.setProtected(true);
    await fixture.store.refresh();
    expect(fixture.requests, hasLength(2));
    fixture.replies[1].complete({'errCode': 0});
    await fixture.waitRequests(3);
    expect(fixture.store.busy.value, isTrue);
    fixture.replies[2].complete(_state(false));
    await write;
    expect(fixture.requests.map((request) => request.method),
        ['GET', 'PUT', 'GET']);
    expect(fixture.store.protect.value, isFalse);
    expect(fixture.store.ready.value, isTrue);
    expect(fixture.store.busy.value, isFalse);
    fixture.store.dispose();
  });

  test('PUT timeout still reconciles current state through GET', () async {
    final fixture = _Fixture();
    await fixture.seed();
    final write = fixture.store.setProtected(false);
    await fixture.waitRequests(2);
    fixture.replies[1].completeError(TimeoutException('write uncertain'));
    await fixture.waitRequests(3);
    fixture.replies[2].complete(_state(false));
    await write;
    expect(fixture.notices, hasLength(1));
    expect(fixture.store.protect.value, isFalse);
    expect(fixture.store.ready.value, isTrue);
    fixture.store.dispose();
  });

  test('invalid session prevents a late PUT from starting reconciliation',
      () async {
    final fixture = _Fixture();
    await fixture.seed();
    final write = fixture.store.setProtected(false);
    await fixture.waitRequests(2);
    fixture.token = 'new-token';
    // A refresh while the write is busy must still revoke the old session.
    await fixture.store.refresh();
    expect(fixture.store.ready.value, isFalse);
    expect(fixture.store.protect.value, isFalse);
    fixture.replies[1].complete({'errCode': 0});
    await write;
    expect(fixture.requests, hasLength(2));
    expect(fixture.store.canManage.value, isFalse);
    expect(fixture.store.busy.value, isFalse);
    fixture.store.dispose();
  });

  test('SDK change during reconciliation rejects its late state', () async {
    final fixture = _Fixture();
    await fixture.seed();
    final write = fixture.store.setProtected(false);
    await fixture.waitRequests(2);
    fixture.replies[1].complete({'errCode': 0});
    await fixture.waitRequests(3);
    fixture.sdkOwner = 'im_other';
    fixture.replies[2].complete(_state(true));
    await write;
    expect(fixture.store.ready.value, isFalse);
    expect(fixture.store.protect.value, isFalse);
    expect(fixture.store.canManage.value, isFalse);
    fixture.store.dispose();
  });

  test('dispose clears displayed state and rejects a pending response',
      () async {
    final fixture = _Fixture();
    await fixture.seed();
    final read = fixture.store.refresh();
    await fixture.waitRequests(2);
    fixture.store.dispose();
    expect(fixture.store.ready.value, isFalse);
    expect(fixture.store.protect.value, isFalse);
    expect(fixture.store.canManage.value, isFalse);
    fixture.replies[1].complete(_state(true));
    await read;
    await fixture.store.refresh();
    await fixture.store.setProtected(false);
    expect(fixture.requests, hasLength(2));
    expect(fixture.store.ready.value, isFalse);
    expect(fixture.store.busy.value, isFalse);
  });

  test('dispose suppresses old write errors and skips GET reconciliation',
      () async {
    final fixture = _Fixture();
    await fixture.seed();
    final write = fixture.store.setProtected(false);
    await fixture.waitRequests(2);
    fixture.store.dispose();
    fixture.replies[1].completeError(TimeoutException('old write'));
    await write;
    expect(fixture.notices, isEmpty);
    expect(fixture.requests, hasLength(2));
    expect(fixture.store.ready.value, isFalse);
  });
}
