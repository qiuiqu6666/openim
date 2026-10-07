import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';

import '../../../support/account_privilege_fixture.dart';

class _CapabilitiesApi extends GroupFeatureApi {
  _CapabilitiesApi()
      : super(
            baseUrl: 'https://chat.fixture.test',
            tokenProvider: () => 'chat-token',
            userProvider: () => 'owner');

  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken}) async {
    calls.add(path);
    final groupID = Uri.decodeComponent(path.split('/')[3]);
    return {
      'groupID': groupID,
      'capabilityVersion': 7,
      'sangong': {
        'canConfigure': true,
        'canManage': true,
        'canOpenAgent': true,
        'tenantID': 'verified-tenant',
      },
    };
  }
}

Map<String, dynamic> _summary(int revision, {bool enabled = true}) => {
      'schemaVersion': 1,
      'revision': revision,
      'games': {
        'sangong': {
          'enabled': enabled,
          'manageEntry': enabled,
          'agentEntry': enabled,
        },
      },
    };

GroupInfo _group(String id, num gameType,
        {int? revision, bool enabled = true}) =>
    GroupInfo(
      groupID: id,
      ex: jsonEncode({
        'gameType': gameType,
        if (revision != null)
          'groupFeatures': _summary(revision, enabled: enabled),
      }),
    );

void main() {
  late _CapabilitiesApi api;
  late FixtureAccountPrivilege privilege;
  late GroupFeatureStore store;

  GroupFeatureContext context(String id) => store.context(
      id: id, name: id, userID: 'owner', admin: false, current: () => true);

  setUp(() {
    api = _CapabilitiesApi();
    privilege = FixtureAccountPrivilege(allowed: false);
    store = GroupFeatureStore(
      api: api,
      accountPrivilege: privilege,
      sessionCurrent: () => true,
      fetchGroups: (_) async => [],
    );
  });
  tearDown(() {
    store.dispose();
    privilege.dispose();
  });

  test('direct contexts and uncached groups use the ordinary type', () {
    final direct = GroupFeatureContext(
      groupID: 'g',
      groupName: 'group',
      currentUserID: 'owner',
      api: api,
      accountPrivilege: privilege,
      sessionCurrent: () => true,
      onFeaturesChanged: (_) {},
    );
    expect(direct.gameType, GroupGameType.ordinary);
    expect(context('uncached').gameType, GroupGameType.ordinary);
    expect(api.calls, isEmpty);
  });

  test('type metadata alone never grants permissions, tenant or a summary', () {
    store.seed(GroupInfo(
        groupID: 'g',
        ex: jsonEncode({
          'gameType': 1,
          'tenantID': 'unverified-tenant',
          'sangong': {'canManage': true, 'canConfigure': true},
        })));
    final snapshot = context('g');
    expect(snapshot.gameType, GroupGameType.sangong);
    expect(snapshot.features.valid, isFalse);
    expect(snapshot.features.sangong.enabled, isFalse);
    expect(snapshot.features.sangong.tenantID, isEmpty);
    expect(snapshot.capabilities.sangong.canManage, isFalse);
    expect(snapshot.capabilities.sangong.canConfigure, isFalse);
    expect(snapshot.capabilities.sangong.canOpenAgent, isFalse);
    expect(snapshot.capabilities.sangong.tenantID, isEmpty);
    expect(snapshot.privilege.allows(userID: 'owner', baseUrl: api.baseUrl),
        isFalse);
    expect(api.calls, isEmpty);
  });

  test('same and older summary revisions still notify independent type changes',
      () async {
    privilege.setAllowed(true);
    store.seed(_group('g', 1, revision: 5));
    await store.loadCapabilities('g');
    const live =
        GroupLiveFeature(status: 'live', sessionID: 'projected-session');
    store.applyLiveState('g', live);
    final previous = context('g');
    final summary = store.features('g');
    final capabilities = store.capabilities('g');
    var notifications = 0;
    store.addListener(() => notifications++);
    final events = <Map<String, dynamic>>[];
    final subscription = store.events('g').listen(events.add);
    addTearDown(subscription.cancel);

    store.seed(_group('g', 3, revision: 5, enabled: false));
    expect(notifications, 1);
    expect(context('g').gameType, GroupGameType.markSix);
    store.seed(_group('g', 3, revision: 5, enabled: false));
    expect(notifications, 1);
    store.seed(_group('g', 0, revision: 4, enabled: false));
    expect(notifications, 2);
    expect(context('g').gameType, GroupGameType.ordinary);
    expect(previous.gameType, GroupGameType.sangong);
    expect(previous.readCurrentContext().gameType, GroupGameType.ordinary);
    expect(store.features('g'), same(summary));
    expect(store.features('g').sangong.enabled, isTrue);
    expect(store.liveFeature('g'), same(live));
    expect(store.capabilities('g'), same(capabilities));
    expect(context('g').capabilities.sangong.tenantID, 'verified-tenant');
    expect(previous.capabilitiesCurrent(), isTrue);
    expect(api.calls, hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });

  test('pending SDK mirrors update type without replacing business state', () {
    store.seed(_group('g', 0, revision: 3));
    context('g').acceptFeatures(_summary(7), mirrorPending: true);
    const live = GroupLiveFeature(status: 'live', sessionID: 'pending-session');
    store.applyLiveState('g', live);
    final summary = store.features('g');
    var notifications = 0;
    store.addListener(() => notifications++);

    store.seed(_group('g', 1, revision: 3, enabled: false));
    expect(notifications, 1);
    expect(context('g').gameType, GroupGameType.sangong);
    store.seed(_group('g', 3));
    expect(notifications, 2);
    expect(context('g').gameType, GroupGameType.markSix);
    store.seed(GroupInfo(groupID: 'g', ex: 'not-json'));
    expect(notifications, 3);
    expect(context('g').gameType, GroupGameType.ordinary);
    expect(store.features('g'), same(summary));
    expect(store.features('g').revision, 7);
    expect(store.liveFeature('g'), same(live));
    expect(store.cachedGroupInfo('g')?.ex, 'not-json');
    expect(context('g').capabilities.sangong.canManage, isFalse);
    expect(context('g').capabilities.sangong.tenantID, isEmpty);
    expect(api.calls, isEmpty);
  });

  test('type metadata is isolated by group ID and removal drops the old type',
      () {
    store.seed(_group('g', 1, revision: 1));
    store.seed(_group('h', 2, revision: 1));
    expect(context('h').gameType, GroupGameType.markSixAgent);
    expect(context('h').showMarkSixDrawHistory, isFalse);
    store.seed(_group('h', 4, revision: 1));
    expect(context('h').gameType, GroupGameType.sangongAgent);
    expect(context('h').showMarkSixDrawHistory, isFalse);
    expect(context('h').capabilities.sangong.canOpenAgent, isFalse);
    store.seed(_group('h', 3, revision: 1));
    expect(context('g').gameType, GroupGameType.sangong);
    expect(context('h').gameType, GroupGameType.markSix);
    expect(context('h').showMarkSixDrawHistory, isTrue);
    store.seed(_group('g', 0, revision: 1));
    expect(context('g').gameType, GroupGameType.ordinary);
    expect(context('h').gameType, GroupGameType.markSix);
    store.seed(_group('g', 1, revision: 1));
    final removed = context('g');
    store.remove('g');
    store.seed(_group('g', 1, revision: 2));
    expect(context('g').gameType, GroupGameType.ordinary);
    expect(context('g').sessionCurrent(), isFalse);
    expect(removed.sessionCurrent(), isFalse);
    expect(store.cachedGroupInfo('g'), isNull);
    expect(context('h').gameType, GroupGameType.markSix);
    expect(context('h').capabilities.sangong.canManage, isFalse);
    expect(api.calls, isEmpty);
  });

  test('clear removes the previous type, summary and private capabilities',
      () async {
    store.seed(_group('g', 1, revision: 2));
    await store.loadCapabilities('g');
    expect(context('g').capabilities.sangong.canManage, isTrue);
    store.clear();

    expect(context('g').gameType, GroupGameType.ordinary);
    expect(store.cachedGroupInfo('g'), isNull);
    expect(context('g').features.valid, isFalse);
    expect(context('g').capabilities.sangong.canManage, isFalse);
    expect(context('g').capabilities.sangong.tenantID, isEmpty);
    store.seed(_group('g', 3));
    expect(context('g').gameType, GroupGameType.markSix);
    expect(context('g').capabilities.sangong.canManage, isFalse);
    expect(api.calls, hasLength(1));
  });

  test('seeding and reading type never rewrite the SDK ex', () {
    const ex = ' {"gameType":1.0,"custom":{"caption":"保留"}} ';
    final sdkGroup = GroupInfo(groupID: 'g', ex: ex);
    store.seed(sdkGroup);
    expect(sdkGroup.ex, ex);
    expect(store.cachedGroupInfo('g')?.ex, ex);
    expect(context('g').gameType, GroupGameType.sangong);
    sdkGroup.ex = '{"gameType":3}';
    expect(context('g').gameType, GroupGameType.sangong);
    expect(store.cachedGroupInfo('g')?.ex, ex);
    expect(api.calls, isEmpty);
  });
}
