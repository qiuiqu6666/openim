import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';

class _Api extends GroupFeatureApi {
  String node = 'https://first.example';
  final responses = <Completer<Map<String, dynamic>>>[];
  @override
  String get baseUrl => node;
  @override
  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken}) {
    final response = Completer<Map<String, dynamic>>();
    responses.add(response);
    return response.future;
  }
}

void main() {
  testWidgets('old-node metadata is discarded and retried on the current node',
      (tester) async {
    final api = _Api();
    final pending = Completer<List<GroupInfo>>();
    var reads = 0;
    final store = GroupFeatureStore(
        api: api,
        sessionCurrent: () => true,
        fetchGroups: (_) {
          reads++;
          return reads == 1
              ? pending.future
              : Future.value([GroupInfo(groupID: 'g', groupName: 'current')]);
        });
    store.hydrate(['g']);
    await tester.pump();
    api.node = 'https://second.example';
    pending.complete([GroupInfo(groupID: 'g', groupName: 'stale')]);
    await tester.pump();
    expect(store.cachedGroupInfo('g'), isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(store.cachedGroupInfo('g')?.groupName, 'current');
    expect(reads, 2);
    store.dispose();
  });

  test('old-node permission failure does not negative-cache the new node',
      () async {
    final api = _Api();
    final store = GroupFeatureStore(
        api: api, sessionCurrent: () => true, fetchGroups: (_) async => []);
    final first = store.loadCapabilities('g');
    api.node = 'https://second.example';
    api.responses.first.completeError(
        const GroupFeatureException('route changed', code: 'SESSION_CHANGED'));
    await first;
    expect(store.capabilityError('g'), isNull);
    final second = store.loadCapabilities('g');
    expect(api.responses.length, 2);
    api.responses.last.complete({'groupID': 'g', 'version': 1});
    await second;
    store.dispose();
  });

  test('retired store ignores pending metadata and permission responses',
      () async {
    final api = _Api();
    final pending = Completer<List<GroupInfo>>();
    final store = GroupFeatureStore(
        api: api,
        sessionCurrent: () => true,
        fetchGroups: (_) => pending.future);
    store.hydrate(['g']);
    final permission = store.loadCapabilities('g');
    await Future<void>.delayed(Duration.zero);
    store.retireSession();
    var changes = 0;
    store.addListener(() => changes++);
    pending.complete([GroupInfo(groupID: 'g', groupName: 'old account')]);
    api.responses.first.complete({'groupID': 'g', 'version': 1});
    await permission;
    await Future<void>.delayed(Duration.zero);
    expect(store.active, isFalse);
    expect(store.cachedGroupInfo('g'), isNull);
    expect(store.capabilityError('g'), isNull);
    expect(changes, 0);
    store.dispose();
  });
}
