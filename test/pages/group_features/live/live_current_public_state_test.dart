import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/data/live_api.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'live_test_support.dart';

Map<String, dynamic> _summary(int revision,
        {String status = 'ready', String id = 'live-1'}) =>
    {
      'schemaVersion': 1,
      'revision': revision,
      'live': {'status': status, 'sessionID': id},
      'games': {
        'sangong': {'enabled': true, 'gameID': 'real-game'},
        'markSix': {'enabled': true}
      }
    };

GroupInfo _group(Map<String, dynamic> summary) =>
    GroupInfo(groupID: 'group#1', ex: jsonEncode({'groupFeatures': summary}));

void main() {
  late GroupFeatureStore store;
  late LiveTransport transport;
  late Map<String, dynamic> response;
  Completer<Map<String, dynamic>>? deferred;
  var accountCurrent = true, routeCurrent = true, disposed = false;
  GroupFeatureContext context() => store.context(
      id: 'group#1',
      name: '直播群',
      userID: 'self',
      admin: false,
      current: () => routeCurrent);
  LiveApi liveApi() => LiveApi(context());

  setUp(() {
    accountCurrent = true;
    routeCurrent = true;
    disposed = false;
    deferred = null;
    response = {'active': true, 'session': liveDTO()};
    transport = LiveTransport((_) => deferred?.future ?? response);
    store = GroupFeatureStore(
        api: transport.api(),
        sessionCurrent: () => accountCurrent,
        fetchGroups: (_) async => []);
  });
  tearDown(() {
    if (!disposed) store.dispose();
  });

  test('a current DTO discovers live without inventing group metadata',
      () async {
    final events = <Map<String, dynamic>>[];
    final subscription = store.events('group#1').listen(events.add);
    var notifications = 0;
    store.addListener(() => notifications++);
    final result = await liveApi().current();
    await Future<void>.delayed(Duration.zero);
    expect(result?.id, 'live-1');
    final badge = store.liveFeature('group#1');
    expect(badge.isActive, true);
    expect(badge.status, 'ready');
    expect(badge.roomName, '每日直播');
    expect(badge.description, '和大家边看边聊');
    expect(badge.anchorUserID, 'anchor');
    expect(store.features('group#1').valid, false);
    expect(store.features('group#1').revision, -1);
    expect(store.features('group#1').sangong.enabled, false);
    expect(store.capabilities('group#1').live.canManage, false);
    expect(context().liveFeature, same(badge));
    expect(context().features.live.isActive, false);
    expect(events, isEmpty);
    expect(notifications, 1);
    await subscription.cancel();
  });

  for (final (status, projected) in [
    ('AUTHORIZED', 'ready'),
    ('LIVE', 'live'),
    ('SCHEDULED', 'scheduled')
  ]) {
    test('current $status maps to the public $projected badge', () async {
      response = {'active': true, 'session': liveDTO(status: status)};
      await liveApi().current();
      expect(store.liveFeature('group#1').status, projected);
      expect(store.liveFeature('group#1').isActive, true);
      if (status == 'SCHEDULED') {
        expect(store.liveFeature('group#1').scheduledStartAt, isNotNull);
      }
    });
  }

  test('real no-current result removes a cached live badge without a summary',
      () async {
    store.seed(_group(_summary(20)));
    final publicSummary = store.features('group#1');
    response = {'active': false};
    expect(await liveApi().current(), isNull);
    expect(store.liveFeature('group#1').isActive, false);
    expect(store.liveFeature('group#1').sessionID, isEmpty);
    expect(store.features('group#1'), same(publicSummary));
    expect(store.features('group#1').live.isActive, true);
    expect(store.features('group#1').sangong.enabled, true);
    expect(context().liveState, isNotNull);
    expect(context().liveFeature.isActive, false);
  });

  test('session version is independent from the group-summary revision',
      () async {
    store.seed(_group(_summary(9000)));
    response = {
      'active': true,
      'session': liveDTO(id: 'new-session', status: 'LIVE', version: 1)
    };
    await liveApi().current();
    expect(store.liveFeature('group#1').sessionID, 'new-session');
    expect(store.liveFeature('group#1').status, 'live');
    expect(store.features('group#1').revision, 9000);
  });

  test('minimum same-session version rejects old DTO before any publication',
      () async {
    response = {'active': true, 'session': liveDTO(status: 'LIVE', version: 7)};
    final accepted = await liveApi().current();
    final projection = store.liveFeature('group#1');
    final summary = store.features('group#1');
    var notifications = 0;
    store.addListener(() => notifications++);
    response = {
      'active': true,
      'session': liveDTO(status: 'AUTHORIZED', version: 6),
      'groupFeatures': _summary(3),
    };
    await expectLater(
        liveApi().current(minimumSession: accepted),
        throwsA(isA<GroupFeatureException>()
            .having((error) => error.code, 'code', 'STALE_RESPONSE')));
    expect(store.liveFeature('group#1'), same(projection));
    expect(store.features('group#1'), same(summary));
    expect(notifications, 0);
  });

  test('minimum version still accepts a newer DTO, another session and no live',
      () async {
    final minimum = liveSession(status: LiveStatus.live, version: 7);
    response = {'active': true, 'session': liveDTO(status: 'LIVE', version: 8)};
    expect((await liveApi().current(minimumSession: minimum))?.version, 8);
    response = {
      'active': true,
      'session': liveDTO(id: 'next-session', status: 'AUTHORIZED', version: 1),
    };
    expect(
        (await liveApi().current(minimumSession: minimum))?.id, 'next-session');
    response = {'active': false};
    expect(await liveApi().current(minimumSession: minimum), isNull);
    expect(store.liveFeature('group#1').isActive, false);
  });

  test('repeated identical live reads do not notify or publish new summaries',
      () async {
    var notifications = 0;
    store.addListener(() => notifications++);
    await liveApi().current();
    await liveApi().current();
    expect(notifications, 1);
    expect(store.features('group#1').revision, -1);
  });

  test('a context without a projection uses its canonical live summary', () {
    final features = GroupFeatures.fromJson(_summary(3));
    final fallback = GroupFeatureContext(
        groupID: 'group#1',
        groupName: '直播群',
        currentUserID: 'self',
        api: store.api,
        features: features,
        sessionCurrent: () => true,
        onFeaturesChanged: (_) {});
    expect(fallback.liveState, isNull);
    expect(fallback.liveFeature, same(features.live));
  });

  test('cached group metadata is cloned on input and every read', () {
    final original = _group(_summary(3))
      ..groupName = '直播群'
      ..notification = '首屏公告'
      ..notificationUpdateTime = 12;
    store.seed(original);
    original.notification = '外部变更';
    final cached = store.cachedGroupInfo('group#1')!;
    expect(cached.notification, '首屏公告');
    expect(cached.notificationUpdateTime, 12);
    cached.notification = '页面变更';
    expect(store.cachedGroupInfo('group#1')!.notification, '首屏公告');
    expect(store.cachedGroupInfo('other-group'), isNull);
    expect(store.cachedGroupInfo('group#1'), isNot(same(cached)));
  });

  test('cached group metadata cannot cross inactive or left scopes', () {
    store.seed(_group(_summary(3)));
    expect(store.cachedGroupInfo('group#1'), isNotNull);
    accountCurrent = false;
    expect(store.cachedGroupInfo('group#1'), isNull);
    accountCurrent = true;
    store.remove('group#1');
    expect(store.cachedGroupInfo('group#1'), isNull);
    store.seed(_group(_summary(4)));
    expect(store.cachedGroupInfo('group#1'), isNull);
  });

  for (final source in ['SDK', 'business']) {
    test('a newer $source summary clears the current-state projection',
        () async {
      store.seed(_group(_summary(3)));
      response = {'active': true, 'session': liveDTO(status: 'LIVE')};
      await liveApi().current();
      expect(store.liveFeature('group#1').status, 'live');
      final ended = _summary(4, status: 'ended');
      if (source == 'SDK') {
        store.seed(_group(ended));
      } else {
        store.apply('group#1', ended);
      }
      expect(
          store.liveFeature('group#1'), same(store.features('group#1').live));
      expect(store.liveFeature('group#1').isActive, false);
      expect(store.liveFeature('group#1').status, 'ended');
    });
  }

  test('old SDK summaries cannot restore live after current confirms none',
      () async {
    store.seed(_group(_summary(5)));
    response = {'active': false};
    await liveApi().current();
    store.seed(_group(_summary(4)));
    store.seed(_group(_summary(5)));
    expect(store.liveFeature('group#1').isActive, false);
    expect(store.features('group#1').revision, 5);
  });

  test('pending mirror stays protected until SDK catches up then fails closed',
      () async {
    store.seed(_group(_summary(1)));
    response = {
      'active': true,
      'session': liveDTO(status: 'LIVE'),
      'groupFeatures': _summary(5),
      'imSyncStatus': 'pending'
    };
    await liveApi().current();
    expect(store.features('group#1').revision, 5);
    expect(store.features('group#1').live.status, 'ready');
    expect(store.liveFeature('group#1').status, 'live');
    store.seed(_group(_summary(1)));
    store.seed(GroupInfo(groupID: 'group#1', ex: 'retrying SDK mirror'));
    expect(store.liveFeature('group#1').status, 'live');
    store.seed(_group(_summary(5)));
    expect(store.liveFeature('group#1').status, 'live');
    store.seed(GroupInfo(groupID: 'group#1', ex: 'malformed'));
    expect(store.liveFeature('group#1').isActive, false);
    expect(store.features('group#1').valid, false);
    expect(store.features('group#1').sangong.enabled, false);
  });

  test('non-pending malformed SDK metadata clears a standalone projection',
      () async {
    await liveApi().current();
    store.seed(GroupInfo(groupID: 'group#1', ex: 'malformed'));
    expect(store.liveFeature('group#1').isActive, false);
  });

  test('SDK mirrors missing a summary retain a real standalone projection',
      () async {
    await liveApi().current();
    for (final ex in [null, '', '   ', '{}', '{"otherMetadata":true}']) {
      store.seed(GroupInfo(groupID: 'group#1', ex: ex));
      expect(store.features('group#1').valid, false);
      expect(store.liveFeature('group#1').status, 'ready');
      expect(store.liveFeature('group#1').sessionID, 'live-1');
    }
  });

  test('a formerly valid SDK summary missing now clears the projection',
      () async {
    store.seed(_group(_summary(3)));
    await liveApi().current();
    store.seed(GroupInfo(groupID: 'group#1', ex: ''));
    expect(store.features('group#1').valid, false);
    expect(store.liveFeature('group#1').isActive, false);
  });

  for (final metadata in [
    '{"groupFeatures":null}',
    '{"groupFeatures":{"schemaVersion":2,"revision":3}}',
    '[]',
  ]) {
    test('explicit invalid SDK metadata $metadata clears the projection',
        () async {
      await liveApi().current();
      store.seed(GroupInfo(groupID: 'group#1', ex: metadata));
      expect(store.features('group#1').valid, false);
      expect(store.liveFeature('group#1').isActive, false);
    });
  }

  for (final active in [true, false]) {
    test('new summary during current=$active wins over the late DTO', () async {
      store.seed(_group(_summary(1)));
      deferred = Completer<Map<String, dynamic>>();
      final pending = liveApi().current();
      await Future<void>.delayed(Duration.zero);
      final expected = expectLater(
          pending,
          throwsA(isA<GroupFeatureException>()
              .having((error) => error.code, 'code', 'STALE_RESPONSE')));
      store.apply('group#1', _summary(2, status: 'live', id: 'new-session'));
      deferred!.complete({
        'active': active,
        if (active) 'session': liveDTO(),
      });
      await expected;
      expect(store.liveFeature('group#1').sessionID, 'new-session');
      expect(store.liveFeature('group#1').status, 'live');
      expect(store.features('group#1').revision, 2);
    });
  }

  test('older response summary remains stale before any projection callback',
      () async {
    store.seed(_group(_summary(5, status: 'ended')));
    response = {
      'active': true,
      'session': liveDTO(),
      'groupFeatures': _summary(4)
    };
    await expectLater(
        liveApi().current(),
        throwsA(isA<GroupFeatureException>()
            .having((error) => error.code, 'code', 'STALE_RESPONSE')));
    expect(store.liveFeature('group#1').status, 'ended');
  });

  test('malformed SDK invalidation during the request blocks a late projection',
      () async {
    store.seed(_group(_summary(3)));
    deferred = Completer<Map<String, dynamic>>();
    final pending = liveApi().current();
    await Future<void>.delayed(Duration.zero);
    final expected = expectLater(
        pending,
        throwsA(isA<GroupFeatureException>()
            .having((error) => error.code, 'code', 'STALE_RESPONSE')));
    store.seed(GroupInfo(groupID: 'group#1', ex: 'invalid'));
    deferred!.complete({'active': true, 'session': liveDTO()});
    await expected;
    expect(store.liveFeature('group#1').isActive, false);
  });

  test('cancelled current responses publish no live projection', () async {
    deferred = Completer<Map<String, dynamic>>();
    final token = CancelToken();
    final pending = liveApi().current(cancelToken: token);
    await Future<void>.delayed(Duration.zero);
    final expected = expectLater(pending, throwsA(anything));
    token.cancel('list no longer visible');
    deferred!.complete({'active': true, 'session': liveDTO()});
    await expected;
    expect(store.liveFeature('group#1').isActive, false);
  });

  for (final boundary in ['account', 'route', 'group', 'dispose']) {
    test('$boundary changes block late current-state publication', () async {
      deferred = Completer<Map<String, dynamic>>();
      final pending = liveApi().current();
      await Future<void>.delayed(Duration.zero);
      final expected = expectLater(pending, throwsStateError);
      switch (boundary) {
        case 'account':
          accountCurrent = false;
          store.invalidateSession();
        case 'route':
          routeCurrent = false;
        case 'group':
          store.remove('group#1');
        case 'dispose':
          store.dispose();
          disposed = true;
      }
      deferred!.complete({'active': true, 'session': liveDTO()});
      await expected;
      expect(store.liveFeature('group#1').isActive, false);
    });
  }

  for (final boundary in ['remove', 'clear', 'logout', 'dispose']) {
    test('$boundary clears projected badges immediately', () async {
      await liveApi().current();
      expect(store.liveFeature('group#1').isActive, true);
      switch (boundary) {
        case 'remove':
          store.remove('group#1');
        case 'clear':
          store.clear();
        case 'logout':
          store.invalidateSession();
        case 'dispose':
          store.dispose();
          disposed = true;
      }
      expect(store.liveFeature('group#1').isActive, false);
    });
  }
}
