import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';

class _HTTP implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? respond;
  dynamic data = const {'errCode': 0, 'data': {}};
  int status = 200;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (respond != null) return respond!(options);
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _summary(int version,
        {String live = 'live', bool enabled = true}) =>
    {
      'schemaVersion': 1,
      'revision': version,
      'live': {'status': live, 'sessionID': 'session-1'},
      'games': {
        'sangong': {
          'enabled': enabled,
          'manageEntry': true,
          'agentEntry': true
        },
        'markSix': {
          'enabled': enabled,
          'drawHistoryEntry': true,
          'rebateHistoryEntry': true
        }
      }
    };
void main() {
  late _HTTP http;
  late GroupFeatureApi api;
  late GroupFeatureStore store;
  var active = true, token = 'chat', user = 'me', reads = 0;
  late DateTime now;
  setUp(() {
    active = true;
    token = 'chat';
    user = 'me';
    reads = 0;
    now = DateTime(2026, 10, 4);
    http = _HTTP();
    api = GroupFeatureApi(
        client: Dio()..httpClientAdapter = http,
        baseUrl: 'https://business.example',
        tokenProvider: () => token,
        userProvider: () => user);
    store = GroupFeatureStore(
        api: api,
        sessionCurrent: () => active,
        clock: () => now,
        fetchGroups: (ids) async {
          reads++;
          return [
            for (final id in ids)
              GroupInfo(
                  groupID: id, ex: jsonEncode({'groupFeatures': _summary(1)}))
          ];
        });
  });
  tearDown(() => store.dispose());
  test('missing, malformed, unknown schema and nonboolean switches fail closed',
      () {
    for (final raw in [
      null,
      'bad',
      '[]',
      '{"groupFeatures":{"schemaVersion":2,"revision":3}}'
    ]) {
      final feature = GroupFeatures.fromEx(raw);
      expect(feature.live.isActive, false);
      expect(feature.sangong.enabled, false);
    }
    final next = GroupFeatures.fromJson({
      ..._summary(1),
      'games': {
        'markSix': {'enabled': 'true', 'drawHistoryEntry': 1}
      }
    });
    expect(next.markSix.enabled, false);
    expect(next.markSix.drawHistoryEntry, false);
  });
  test('public switches grant no personal business permissions', () {
    store.apply('g', _summary(1));
    expect(store.features('g').markSix.drawHistoryEntry, true);
    expect(store.capabilities('g').markSix.canOpenAgent, false);
    expect(store.capabilities('g').sangong.canManage, false);
  });
  test('coalesces batch requests and does not fetch again on row/list rebuild',
      () async {
    store.hydrate(['g', 'h']);
    store.hydrate(['g', 'h']);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    store.hydrate(['g']);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    store.refreshKnownGroups();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);
  });
  test('existing SDK metadata is reused without a group lookup', () async {
    store.seed(GroupInfo(
        groupID: 'g', ex: jsonEncode({'groupFeatures': _summary(2)})));
    store.hydrate(['g']);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 0);
    expect(store.features('g').revision, 2);
  });
  test('ended tombstone beats stale push and stale SDK response', () {
    store.apply('g', _summary(12, live: 'ended'));
    store.apply('g', _summary(11));
    store.seed(GroupInfo(
        groupID: 'g', ex: jsonEncode({'groupFeatures': _summary(10)})));
    expect(store.features('g').live.status, 'ended');
    expect(store.features('g').revision, 12);
  });
  test('SDK summary changes reach open routes and revoke the old binding',
      () async {
    store.seed(GroupInfo(
        groupID: 'g', ex: jsonEncode({'groupFeatures': _summary(1)})));
    http.data = {
      'errCode': 0,
      'data': {
        'groupID': 'g',
        'capabilityVersion': 2,
        'sangong': {'canManage': true}
      }
    };
    await store.loadCapabilities('g');
    final original = store.context(
        id: 'g', name: 'Group', userID: 'me', admin: true, current: () => true);
    final updates = <Map<String, dynamic>>[];
    final subscription = store
        .events('g')
        .where((event) => event['key'] == 'groupFeaturesChanged')
        .listen(updates.add);
    store.seed(GroupInfo(
        groupID: 'g',
        ex: jsonEncode({'groupFeatures': _summary(2, enabled: false)})));
    expect(original.capabilitiesCurrent(), false);
    await Future<void>.delayed(Duration.zero);
    expect(updates.length, 1);
    expect(updates.single['key'], 'groupFeaturesChanged');
    expect(updates.single['data']['groupFeatures']['revision'], 2);
    store.seed(GroupInfo(
        groupID: 'g', ex: jsonEncode({'groupFeatures': _summary(1)})));
    await Future<void>.delayed(Duration.zero);
    expect(updates.length, 1);
    expect(store.features('g').sangong.enabled, false);
    await subscription.cancel();
  });
  test('capabilities are singleflight, cached, and independent per group',
      () async {
    http.respond = (request) async => ResponseBody.fromString(
            jsonEncode({
              'errCode': 0,
              'data': {
                'groupID': request.path.contains('/g/') ? 'g' : 'h',
                'capabilityVersion': 2,
                'cacheTTLSeconds': 300,
                'sangong': {'canConfigure': true, 'canManage': false}
              }
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json']
            });
    await Future.wait(
        [store.loadCapabilities('g'), store.loadCapabilities('g')]);
    await store.loadCapabilities('g');
    expect(http.requests.length, 1);
    expect(store.capabilities('g').sangong.canConfigure, true);
    expect(store.features('g').sangong.enabled, false);
    await store.loadCapabilities('h');
    expect(http.requests.length, 2);
    now = now.add(const Duration(minutes: 6));
    await store.loadCapabilities('g');
    expect(http.requests.length, 3);
  });
  test(
      'missing capability backend is negatively cached and manual retry is allowed',
      () async {
    http.status = 404;
    http.data = {'errCode': 404};
    await store.loadCapabilities('g');
    await store.loadCapabilities('g');
    expect(http.requests.length, 1);
    expect(store.capabilityError('g')!.unavailable, true);
    await store.loadCapabilities('g', force: true);
    expect(http.requests.length, 2);
  });
  test('late capabilities after invalidation cannot reauthorize', () async {
    final reply = Completer<ResponseBody>();
    http.respond = (_) => reply.future;
    final pending = store.loadCapabilities('g');
    store.invalidateCapabilities('g');
    reply.complete(ResponseBody.fromString(
        jsonEncode({
          'errCode': 0,
          'data': {
            'groupID': 'g',
            'sangong': {'canManage': true}
          }
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        }));
    await pending;
    expect(store.capabilities('g').sangong.canManage, false);
  });
  test('SDK permission revision refreshes once even with unchanged public entries', () async {
    Map<String, dynamic> caps(int version, bool manage) => {
      'errCode': 0, 'data': {'groupID': 'g', 'capabilityVersion': version,
        'cacheTTLSeconds': 300, 'sangong': {'canManage': manage}}
    };
    store.apply('g', {..._summary(1), 'capabilityVersion': 1});
    http.data = caps(1, true);
    await store.loadCapabilities('g');
    expect(store.capabilities('g').sangong.canManage, isTrue);
    http.data = caps(2, false);
    final mirror = GroupInfo(groupID: 'g', ex: jsonEncode({
      'groupFeatures': {..._summary(2), 'capabilityVersion': 2}
    }));
    store.seed(mirror);
    store.seed(mirror);
    await store.loadCapabilities('g');
    expect(http.requests.length, 2);
    expect(store.capabilities('g').sangong.canManage, isFalse);
    store.seed(GroupInfo(groupID: 'g', ex: jsonEncode({
      'groupFeatures': {..._summary(1), 'capabilityVersion': 1}
    })));
    expect(http.requests.length, 2);
    expect(store.capabilities('g').version, 2);
  });
  test('SDK capability floor rejects an older HTTP permission response', () async {
    store.apply('g', {..._summary(2), 'capabilityVersion': 7});
    http.data = {'errCode': 0, 'data': {'groupID': 'g', 'capabilityVersion': 6,
      'sangong': {'canManage': true}}};
    await store.loadCapabilities('g');
    expect(store.capabilities('g').sangong.canManage, isFalse);
    expect(store.capabilityError('g')?.code, 'STALE_CAPABILITIES');
  });
  test('business events are deduplicated, group-scoped and version checked',
      () async {
    final received = <Map<String, dynamic>>[];
    final subscription = store.events('g').listen(received.add);
    final raw = jsonEncode({
      'key': 'groupFeaturesChanged',
      'eventId': 'event-1',
      'data': {'groupID': 'g', 'groupFeatures': _summary(5)}
    });
    store.receiveBusiness(raw);
    store.receiveBusiness(raw);
    store.receiveBusiness(jsonEncode({
      'key': 'groupFeaturesChanged',
      'eventId': 'event-2',
      'data': {'groupID': 'h', 'groupFeatures': _summary(6)}
    }));
    store.receiveBusiness('malformed');
    await Future<void>.delayed(Duration.zero);
    expect(received.length, 1);
    expect(store.features('g').revision, 5);
    await subscription.cancel();
  });
  test('leave revokes capabilities and rejects late updates', () async {
    store.apply('g', _summary(2));
    store.remove('g');
    store.apply('g', _summary(3));
    expect(store.features('g').live.isActive, false);
    expect(
        store
            .context(
                id: 'g',
                name: 'Group',
                userID: 'me',
                admin: true,
                current: () => true)
            .sessionCurrent(),
        false);
  });
  test('rejected old business summaries cannot retire a newer open binding',
      () async {
    final updates = <Map<String, dynamic>>[];
    final subscription = store.events('g').listen(updates.add);
    final accepted = {
      ..._summary(5),
      'games': {
        'markSix': {
          'enabled': true,
          'drawHistoryEntry': true,
          'machineCode': 'A'
        }
      }
    };
    store.apply('g', accepted);
    store.receiveBusiness(jsonEncode({
      'key': 'groupFeaturesChanged',
      'eventId': 'old-binding',
      'data': {
        'groupID': 'g',
        'groupFeatures': {
          ..._summary(4),
          'games': {
            'markSix': {
              'enabled': true,
              'drawHistoryEntry': true,
              'machineCode': 'B'
            }
          }
        }
      }
    }));
    await Future<void>.delayed(Duration.zero);
    expect(updates.last['data']['groupFeatures']['revision'], 5);
    expect(
        updates.last['data']['groupFeatures']['games']['markSix']
            ['machineCode'],
        'A');
    expect(store.features('g').markSix.machineCode, 'A');
    await subscription.cancel();
  });
  test('older capability events do not invalidate a newer authorization',
      () async {
    http.data = {
      'errCode': 0,
      'data': {
        'groupID': 'g',
        'capabilityVersion': 5,
        'sangong': {'canManage': true}
      }
    };
    await store.loadCapabilities('g');
    final snapshot = store.context(
        id: 'g', name: 'Group', userID: 'me', admin: true, current: () => true);
    store.receiveBusiness(jsonEncode({
      'key': 'groupFeatureCapabilitiesChanged',
      'eventId': 'old-permission',
      'data': {'groupID': 'g', 'capabilityVersion': 4}
    }));
    expect(snapshot.capabilitiesCurrent(), true);
    expect(store.capabilities('g').sangong.canManage, true);
  });
  test('session exit clears cached state and fences open contexts immediately',
      () {
    store.apply('g', _summary(2));
    final original = store.context(
        id: 'g', name: 'Group', userID: 'me', admin: true, current: () => true);
    store.invalidateSession();
    expect(store.features('g').valid, false);
    expect(original.sessionCurrent(), false);
    expect(original.capabilitiesCurrent(), false);
    store.apply('g', _summary(3));
    expect(store.features('g').valid, false);
  });
  test(
      'private authorization snapshot is invalidated independently of public group membership',
      () {
    final snapshot = store.context(
        id: 'g', name: 'Group', userID: 'me', admin: true, current: () => true);
    store.invalidateCapabilities('g', expectedVersion: 3);
    expect(snapshot.sessionCurrent(), true);
    expect(snapshot.capabilitiesCurrent(), false);
    expect(
        store
            .context(
                id: 'g',
                name: 'Group',
                userID: 'me',
                admin: true,
                current: () => true)
            .capabilitiesCurrent(),
        true);
  });
  test(
      'preserved lottery envelope retains server time and list data after code validation',
      () async {
    http.data = {
      'code': 'OK',
      'groupUid': 'g',
      'serverTime': 1791000000000,
      'data': [
        {'issue': '1'}
      ]
    };
    final result =
        await api.getEnvelope('/api/v1/lotteries/mark-six-demo/draws');
    expect(result['serverTime'], 1791000000000);
    expect(result['groupUid'], 'g');
    expect(result['data'], [
      {'issue': '1'}
    ]);
    http.data = {'code': 'FAILED', 'data': []};
    await expectLater(
        api.getEnvelope('/draws'), throwsA(isA<GroupFeatureException>()));
  });
  test(
      'transport uses Chat auth, operationID and recognizes reference and Chat envelopes',
      () async {
    http.data = {
      'errCode': 0,
      'data': {'value': 1}
    };
    expect((await api.get('/current'))['value'], 1);
    http.data = {
      'code': 200,
      'data': [1, 2]
    };
    expect(await api.getData('/rows'), [1, 2]);
    http.data = {'sessionID': 's'};
    expect((await api.get('/session'))['sessionID'], 's');
    expect(http.requests.first.headers['token'], 'chat');
    expect(http.requests.first.headers['operationID'], isNotEmpty);
    expect(http.requests.first.headers.containsKey('Authorization'), false);
  });
  test('token replacement discards an in-flight read', () async {
    final reply = Completer<ResponseBody>();
    http.respond = (_) => reply.future;
    final pending = api.get('/session');
    token = 'new';
    reply.complete(
        ResponseBody.fromString('{"errCode":0,"data":{}}', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    }));
    await expectLater(
        pending,
        throwsA(isA<GroupFeatureException>()
            .having((e) => e.code, 'code', 'SESSION_CHANGED')));
  });
  test('write failure reports an unknown result rather than success', () async {
    http.status = 502;
    http.data = {};
    await expectLater(
        api.post('/settle', body: {}),
        throwsA(isA<GroupFeatureException>()
            .having((e) => e.unknownResult, 'unknown', true)));
  });
  test('UTF-8 SSE preserves split Chinese characters', () async {
    final bytes = utf8.encode('data: {"text":"直播"}\n\n');
    http.respond = (_) => Future.value(ResponseBody(
        Stream.fromIterable([
          Uint8List.fromList(bytes.sublist(0, 18)),
          Uint8List.fromList(bytes.sublist(18))
        ]),
        200));
    expect((await api.eventStream('/events').toList()).join(),
        'data: {"text":"直播"}\n\n');
  });
  test('closing an SSE consumer cancels transport without an unhandled error',
      () async {
    final source = StreamController<Uint8List>();
    final opened = Completer<void>();
    http.respond = (_) async {
      opened.complete();
      return ResponseBody(source.stream, 200);
    };
    final errors = <Object>[];
    final subscription = api
        .eventStream('/events')
        .listen((_) {}, onError: (Object error) => errors.add(error));
    await opened.future;
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    await source.close();
    expect(errors, isEmpty);
  });
  test('SSE discards chunks after an account token changes', () async {
    final source = StreamController<Uint8List>();
    final opened = Completer<void>();
    http.respond = (_) async {
      opened.complete();
      return ResponseBody(source.stream, 200);
    };
    final chunks = <String>[];
    final errors = <Object>[];
    final completed = Completer<void>();
    api.eventStream('/events').listen(chunks.add,
        onError: (Object error) => errors.add(error),
        onDone: completed.complete);
    await opened.future;
    await Future<void>.delayed(Duration.zero);
    token = 'replacement';
    source.add(Uint8List.fromList(utf8.encode('data: old-session\n\n')));
    await completed.future;
    await source.close();
    expect(chunks, isEmpty);
    expect(
        errors.single,
        isA<GroupFeatureException>()
            .having((e) => e.code, 'code', 'SESSION_CHANGED'));
  });
}
