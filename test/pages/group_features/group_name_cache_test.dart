import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/data/group_name_cache.dart';
import 'package:openim/pages/group_features/models/group_game_type.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('group_name_cache');
    Hive.init(directory.path);
    await GroupNameCache.initialize();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  GroupFeatureStore store(String user,
          {Future<List<GroupInfo>> Function(List<String>)? fetch}) =>
      GroupFeatureStore(
        api: GroupFeatureApi(),
        sessionCurrent: () => true,
        fetchGroups: fetch ?? (_) async => [],
        nameCache: GroupNameCache(user),
      );

  test('reopened database restores display synchronously without permissions',
      () async {
    final first = store('alice');
    first.seed(GroupInfo(groupID: 'g', ex: '{"gameType":3}'));
    await Hive.box<dynamic>(GroupNameCache.boxName).flush();
    first.dispose();
    await Hive.close();
    await GroupNameCache.initialize();

    final restarted = store('alice');
    addTearDown(restarted.dispose);
    expect(restarted.gameType('g'), GroupGameType.markSix);
    expect(restarted.cachedGroupInfo('g'), isNull);
    expect(restarted.features('g').valid, isFalse);
    final other = store('bob');
    addTearDown(other.dispose);
    expect(other.gameType('g'), GroupGameType.ordinary);
  });

  test('ordinary updates and leaving replace persisted red metadata', () async {
    final current = store('alice');
    addTearDown(current.dispose);
    current.seed(GroupInfo(groupID: 'g', ex: '{"gameType":1}'));
    current.seed(GroupInfo(groupID: 'g', ex: '{"gameType":0}'));
    await Hive.box<dynamic>(GroupNameCache.boxName).flush();
    expect(GroupNameCache('alice').read('g'), GroupGameType.ordinary);
    current.seed(GroupInfo(groupID: 'g', ex: '{"gameType":1}'));
    current.remove('g');
    await Hive.box<dynamic>(GroupNameCache.boxName).flush();
    expect(GroupNameCache('alice').read('g'), isNull);
  });

  test('cached type survives offline read but still refreshes', () async {
    await GroupNameCache('alice').write('g', GroupGameType.sangong);
    var calls = 0;
    final current = store('alice', fetch: (_) async {
      if (++calls == 1) throw StateError('offline');
      return [GroupInfo(groupID: 'g', ex: '{"gameType":0}')];
    });
    addTearDown(current.dispose);
    current.hydrate(['g']);
    await Future<void>.delayed(Duration.zero);
    expect(current.gameType('g'), GroupGameType.sangong);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(calls, 2);
    expect(current.gameType('g'), GroupGameType.ordinary);
    current.invalidateSession();
    expect(current.gameType('g'), GroupGameType.ordinary);
    await Hive.box<dynamic>(GroupNameCache.boxName).flush();
  });
}
