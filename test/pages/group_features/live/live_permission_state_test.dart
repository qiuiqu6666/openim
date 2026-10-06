import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/data/live_api.dart';
import 'package:openim/pages/group_features/live/data/live_permission_state.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'live_test_support.dart';

Map<String, dynamic> _summary(int revision,
        {String status = 'ready', String anchor = 'anchor'}) =>
    {
      'schemaVersion': 1,
      'revision': revision,
      'live': {
        'status': status,
        'sessionID': status == 'none' ? '' : 'live-1',
        'anchorUserID': anchor,
        'roomName': '每日直播',
      },
      'games': {'sangong': {}, 'markSix': {}},
    };

Map<String, dynamic> _capabilities(int version, {bool canPush = false}) => {
      'groupID': 'group#1',
      'capabilityVersion': version,
      'cacheTTLSeconds': 300,
      'live': {
        'canConfigure': true,
        'canManage': true,
        'canPush': canPush,
        'canTip': true,
        'tipCurrencies': [
          {'code': 'USDT', 'label': 'USDT', 'decimals': 6},
          {'code': 'TRX', 'label': 'TRX', 'decimals': 6},
          {'code': 'BI99', 'label': '99BI', 'decimals': 2},
        ],
      },
      'sangong': {'canConfigure': false},
      'markSix': {'canConfigure': false},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupFeatureStore store;
  late LiveTransport transport;
  late Map<String, dynamic> capabilities;
  var signedIn = true;

  GroupFeatureContext snapshot() => store.context(
      id: 'group#1',
      name: '直播群',
      userID: 'self',
      admin: true,
      current: () => signedIn);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    signedIn = true;
    capabilities = _capabilities(1);
    transport = LiveTransport((request) {
      if (request.path.endsWith('/feature-capabilities')) {
        return {'errCode': 0, 'data': capabilities};
      }
      if (request.path.endsWith('/authorize')) {
        capabilities = _capabilities(2, canPush: true);
        return {
          'errCode': 0,
          'data': {
            ...liveDTO(),
            'groupFeatures': _summary(2),
            'imSyncStatus': 'pending',
          },
        };
      }
      throw StateError('Unexpected route ${request.path}');
    });
    store = GroupFeatureStore(
        api: transport.api(),
        sessionCurrent: () => signedIn,
        fetchGroups: (_) async => []);
  });
  tearDown(() => store.dispose());

  test('successful creation refreshes push permission in the open route once',
      () async {
    store.apply('group#1', _summary(1, status: 'none'));
    await store.loadCapabilities('group#1');
    final initial = snapshot();
    final first = LivePermissionState(initial);
    final second = LivePermissionState(initial);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(first.context.capabilities.live.canPush, false);

    final created = await LiveApi(initial)
        .configure(name: '每日直播', description: '', anchorID: 'anchor');
    expect(created.id, 'live-1');
    expect(initial.sessionCurrent(), true);
    expect(initial.capabilitiesCurrent(), false);
    await Future.wait([first.refresh(), second.refresh()]);
    await flush();
    expect(first.current, true);
    expect(first.context.capabilities.live.canPush, true);
    expect(second.context.capabilities.live.canPush, true);
    expect(store.features('group#1').revision, 2);
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/feature-capabilities'))
            .length,
        2);
    expect(
        transport.requests.where((request) => request.method == 'POST').length,
        1);
  });

  test('pending mirror cannot erase a committed summary with old or invalid ex',
      () async {
    await store.loadCapabilities('group#1');
    await LiveApi(snapshot())
        .configure(name: '每日直播', description: '', anchorID: 'anchor');
    store.seed(GroupInfo(groupID: 'group#1', ex: 'legacy non-json value'));
    store.seed(GroupInfo(
        groupID: 'group#1',
        ex: jsonEncode({'groupFeatures': _summary(1, status: 'none')})));
    expect(store.features('group#1').revision, 2);
    expect(store.features('group#1').live.isActive, true);
    store.seed(GroupInfo(
        groupID: 'group#1', ex: jsonEncode({'groupFeatures': _summary(2)})));
    store.seed(
        GroupInfo(groupID: 'group#1', ex: 'malformed after mirror synced'));
    expect(store.features('group#1').valid, false);
    await flush();
  });

  test(
      'personal anchor notice merges permission refreshes without group version',
      () async {
    store.apply('group#1', _summary(100));
    await store.loadCapabilities('group#1');
    final initial = snapshot();
    final first = LivePermissionState(initial);
    final second = LivePermissionState(initial);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    capabilities = _capabilities(2, canPush: true);
    store.receiveBusiness(jsonEncode({
      'key': 'groupFeatureCapabilitiesChanged',
      'eventId': 'anchor-appointed',
      'data': {'groupID': 'group#1', 'capabilityVersion': 2},
    }));
    expect(first.current, false);
    await flush();
    await Future.wait([first.refresh(), second.refresh()]);
    await flush();
    expect(first.context.capabilities.version, 2);
    expect(second.context.capabilities.live.canPush, true);
    expect(store.features('group#1').revision, 100);
    expect(transport.requests.length, 2);
  });

  test('identical refreshed currency objects do not retire private snapshots',
      () async {
    await store.loadCapabilities('group#1');
    final initial = snapshot();
    capabilities = _capabilities(1); // fresh list/map identities, same values
    final updated = await initial.refreshCapabilities(force: true);
    expect(updated.capabilities.live.canConfigure, true);
    expect(initial.capabilitiesCurrent(), true);
    capabilities = _capabilities(2, canPush: true);
    final changed = await updated.refreshCapabilities(force: true);
    expect(initial.capabilitiesCurrent(), false);
    expect(updated.capabilitiesCurrent(), false);
    expect(changed.capabilitiesCurrent(), true);
    expect(changed.capabilities.live.canPush, true);
  });

  test('background private route retains invalidation until foreground refresh',
      () async {
    await store.loadCapabilities('group#1');
    final state = LivePermissionState(snapshot())..setActive(false);
    addTearDown(state.dispose);
    capabilities = _capabilities(2, canPush: true);
    store.receiveBusiness(jsonEncode({
      'key': 'groupFeatureCapabilitiesChanged',
      'data': {'groupID': 'group#1', 'capabilityVersion': 2},
    }));
    await flush();
    expect(state.current, false);
    expect(transport.requests.length, 1);
    state.setActive(true);
    await state.refresh();
    expect(state.context.capabilities.live.canPush, true);
    expect(transport.requests.length, 2);
  });

  test('refresh cannot adopt another account after sign-out or leave',
      () async {
    await store.loadCapabilities('group#1');
    final state = LivePermissionState(snapshot());
    addTearDown(state.dispose);
    store.remove('group#1');
    await expectLater(state.refresh(), throwsA(isA<Exception>()));
    expect(state.sessionCurrent, false);
    expect(state.current, false);
    expect(store.features('group#1').valid, false);
    expect(transport.requests.length, 1);
  });

  test('failed permission refresh cannot retain an old push authorization',
      () async {
    capabilities = _capabilities(2, canPush: true);
    await store.loadCapabilities('group#1');
    final initial = snapshot();
    final state = LivePermissionState(initial);
    addTearDown(state.dispose);
    transport.status = 503;
    await expectLater(state.refresh(force: true), throwsA(isA<Exception>()));
    await flush();
    expect(initial.capabilitiesCurrent(), false);
    expect(state.current, false);
    expect(store.capabilities('group#1').live.canPush, false);
    expect(transport.requests.length, 2);
    transport.status = 200;
    capabilities = _capabilities(3, canPush: false);
    await state.refresh(force: true);
    expect(state.current, true);
    expect(state.context.capabilities.live.canPush, false);
  });

  test(
      'an active public status without a session id never exposes a live entry',
      () {
    expect(GroupLiveFeature.fromJson({'status': 'live'}).isActive, false);
  });
}
