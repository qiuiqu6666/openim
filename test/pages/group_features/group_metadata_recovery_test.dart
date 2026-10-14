import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/identity/group_name_label.dart';
import 'package:openim/pages/group_features/models/group_game_type.dart';

GroupInfo group(String id, int type) =>
    GroupInfo(groupID: id, ex: '{"gameType":$type}');

void main() {
  testWidgets('failed list read retries and updates the mounted name',
      (tester) async {
    var calls = 0;
    final store = GroupFeatureStore(
      api: GroupFeatureApi(),
      sessionCurrent: () => true,
      fetchGroups: (ids) async {
        if (++calls == 1) throw StateError('offline');
        return [group('g', 3), group('ordinary', 0), group('agent', 2)];
      },
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      for (final id in ['g', 'ordinary', 'agent'])
        GroupNameLabel(name: id, groupID: id, store: store),
    ])));
    store.hydrate(['g', 'ordinary', 'agent']);
    await tester.pump();
    expect(calls, 1);
    for (var i = 0; i < 10; i++) {
      store.hydrate(['g']);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(calls, 4);
    final context = tester.element(find.text('g'));
    expect(tester.widget<Text>(find.text('g')).style?.color,
        groupNameColor(context, GroupGameType.markSix));
    expect(tester.widget<Text>(find.text('ordinary')).style?.color, isNull);
    expect(tester.widget<Text>(find.text('agent')).style?.color, isNull);
    store.hydrate(['g', 'ordinary', 'agent']);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 4);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('partial response retries only missing groups', (tester) async {
    final reads = <List<String>>[];
    final store = GroupFeatureStore(
      api: GroupFeatureApi(),
      sessionCurrent: () => true,
      fetchGroups: (ids) async {
        reads.add(List.of(ids));
        return reads.length == 1 ? [group('a', 1)] : [group('b', 3)];
      },
    );
    addTearDown(store.dispose);
    store.hydrate(['a', 'b']);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, [
      ['a', 'b'],
      ['b']
    ]);
    expect(store.gameType('a'), GroupGameType.sangong);
    expect(store.gameType('b'), GroupGameType.markSix);
  });

  testWidgets('late list result cannot overwrite chat or SDK metadata',
      (tester) async {
    final response = Completer<List<GroupInfo>>();
    final store = GroupFeatureStore(
      api: GroupFeatureApi(),
      sessionCurrent: () => true,
      fetchGroups: (_) => response.future,
    );
    addTearDown(store.dispose);
    store.hydrate(['g']);
    await tester.pump();
    store.seed(group('g', 3));
    response.complete([group('g', 0)]);
    await tester.pump();
    expect(store.gameType('g'), GroupGameType.markSix);
    // An actual subsequent type change must still remove the red name.
    store.seed(group('g', 0));
    expect(store.gameType('g'), GroupGameType.ordinary);
  });

  for (final cleanup in ['leave', 'logout', 'dispose', 'none']) {
    testWidgets('missing metadata has bounded retries: $cleanup',
        (tester) async {
      var calls = 0;
      final store = GroupFeatureStore(
        api: GroupFeatureApi(),
        sessionCurrent: () => true,
        fetchGroups: (_) async {
          calls++;
          return [];
        },
      );
      store.hydrate(['g']);
      await tester.pump();
      if (cleanup == 'leave') store.remove('g');
      if (cleanup == 'logout') store.invalidateSession();
      if (cleanup == 'dispose') store.dispose();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 30));
      expect(calls, cleanup == 'none' ? 3 : 1);
      if (cleanup != 'dispose') store.dispose();
    });
  }
}
