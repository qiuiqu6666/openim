import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/group_features/personalization/group_personalization.dart';
import 'package:openim/pages/group_features/identity/group_name_label.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('game types never override owner appearance or default: $dark',
        (tester) async {
      for (final game in [0, 1, 2, 3]) {
        final base = '{"gameType":$game}';
        for (final chosen in <int?>[null, 0xFFDC2626]) {
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light),
              home: GroupNameLabel(
                  name: 'Group',
                  ex: GroupPersonalization(color: chosen).mergeInto(base),
                  style: const TextStyle(color: Colors.grey))));
          expect(tester.widget<Text>(find.text('Group')).style?.color,
              chosen == null ? Colors.grey : Color(chosen));
        }
      }
    });
  }

  test('merge preserves unrelated group metadata and reset removes appearance',
      () {
    const value = GroupPersonalization(
        color: 0xFF1677D2, iconUrl: 'https://example.com/icon.png');
    final ex = value.mergeInto(
        '{"gameType":3,"groupFeatures":{"revision":9},"conversationKind":"channel"}');
    expect(jsonDecode(ex)['groupFeatures']['revision'], 9);
    expect(jsonDecode(ex)['conversationKind'], 'channel');
    expect(jsonDecode(ex)['gameType'], 3);
    expect(GroupPersonalization.fromEx(ex).color, value.color);
    expect(GroupPersonalization.fromEx(ex).iconUrl, value.iconUrl);
    final reset = const GroupPersonalization().mergeInto(ex);
    expect(GroupPersonalization.fromEx(reset).color, isNull);
    expect(GroupPersonalization.fromEx(reset).iconUrl, isNull);
    expect(jsonDecode(reset)['gameType'], 3);
  });
  test('preset icon round trips and unknown presets are ignored', () {
    final ex = const GroupPersonalization(iconKey: 'heart').mergeInto(null);
    expect(GroupPersonalization.fromEx(ex).iconKey, 'heart');
    expect(
        GroupPersonalization.fromEx(const GroupPersonalization().mergeInto(ex))
            .iconKey,
        isNull);
    expect(
        GroupPersonalization.fromEx(
                const GroupPersonalization(iconKey: 'unknown').mergeInto(null))
            .iconKey,
        isNull);
  });
  test('malformed data is safe to render but never overwritten by save', () {
    for (final ex in ['broken', '[]', '42']) {
      expect(GroupPersonalization.fromEx(ex).color, isNull);
      expect(() => const GroupPersonalization().mergeInto(ex),
          throwsFormatException);
    }
    expect(
        GroupPersonalization.fromEx(
                '{"groupPersonalization":{"version":1,"color":1,"iconUrl":"file:///private"}}')
            .iconUrl,
        isNull);
    expect(
        GroupPersonalization.fromEx(
                '{"groupPersonalization":{"version":1,"color":1}}')
            .color,
        isNull);
  });
  testWidgets(
      'SDK update refreshes visible name even with unchanged feature revision',
      (tester) async {
    final store = GroupFeatureStore(
        api: GroupFeatureApi(),
        sessionCurrent: () => true,
        fetchGroups: (_) async => []);
    addTearDown(store.dispose);
    const base = '{"groupFeatures":{"schemaVersion":1,"revision":9}}';
    store.seed(GroupInfo(groupID: 'g', ex: base));
    await tester.pumpWidget(MaterialApp(
        home: GroupNameLabel(name: 'Group', groupID: 'g', store: store)));
    store.seed(GroupInfo(
        groupID: 'g',
        ex: const GroupPersonalization(color: 0xFF1677D2).mergeInto(base)));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Group')).style?.color,
        const Color(0xFF1677D2));
    store.seed(GroupInfo(
        groupID: 'g', ex: const GroupPersonalization().mergeInto(base)));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Group')).style?.color, isNull);
    expect(tester.takeException(), isNull);
  });
}
