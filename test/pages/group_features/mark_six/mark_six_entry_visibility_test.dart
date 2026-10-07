import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/mark_six/pages/mark_six_page.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_feature_host.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';

import '../../../support/account_privilege_fixture.dart';
import '../../../support/performance/render_test_fakes.dart';
import 'mark_six_fixtures.dart';

const _handle = ValueKey('lottery-edge-handle');

void main() {
  late MarkSixFakeApi api;
  late FixtureAccountPrivilege privilege;
  late GroupFeatureStore store;

  void seed(int type, {String? machine}) => store.seed(GroupInfo(
      groupID: 'group-test',
      ex: jsonEncode({
        'gameType': type,
        if (machine != null)
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 1,
            'games': {
              'markSix': {
                'enabled': false,
                'drawHistoryEntry': false,
                'machineCode': machine,
              }
            }
          }
      })));

  GroupFeatureContext current() => store.context(
      id: 'group-test',
      name: '测试群',
      userID: 'self',
      admin: false,
      current: () => true);

  Widget chat() => renderTestHost(ListenableBuilder(
      listenable: store,
      builder: (_, __) => MarkSixFeatureHost(
          featureContext: current(),
          builder: (context, entry, overlay) => Stack(children: [
                Positioned.fill(
                    child: Column(children: [
                  const Text('聊天内容'),
                  for (final item
                      in GroupFeatureActions.items(context, current()))
                    TextButton(onPressed: item.onTap, child: Text(item.text)),
                ])),
                overlay,
              ]))));

  setUp(() {
    api = MarkSixFakeApi();
    privilege = FixtureAccountPrivilege(allowed: false);
    store = GroupFeatureStore(
        api: api,
        accountPrivilege: privilege,
        sessionCurrent: () => true,
        fetchGroups: (_) async => []);
  });
  tearDown(() {
    store.dispose();
    privilege.dispose();
    Get.reset();
  });

  for (final viaHandle in [true, false]) {
    testWidgets(
        'type 3 opens draws via ${viaHandle ? 'edge' : 'toolbox'} without summary or machine',
        (tester) async {
      seed(3);
      await tester.pumpWidget(chat());
      await tester.pumpAndSettle();
      expect(find.byKey(_handle), findsOneWidget);
      expect(find.text('开奖记录'), findsOneWidget);
      expect(find.text('六合彩代理'), findsNothing);
      expect(find.text('反水历史'), findsNothing);
      expect(current().features.markSix.enabled, isFalse);
      expect(current().capabilities.markSix.canOpenAgent, isFalse);
      expect(api.calls, isEmpty);

      if (viaHandle) {
        await tester.tap(find.byKey(_handle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('lottery-preview-open')));
      } else {
        await tester.tap(find.text('开奖记录'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MarkSixPage), findsOneWidget);
      expect(find.textContaining('本群尚未配置六合彩机器码'), findsOneWidget);
      expect(find.text('本群尚未开放六合彩'), findsNothing);
      expect(api.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('type 3 reads its configured draw data with feature flags off',
      (tester) async {
    seed(3, machine: 'current-group-machine');
    await tester.pumpWidget(chat());
    await tester.pumpAndSettle();
    await tester.tap(find.text('开奖记录'));
    await tester.pumpAndSettle();
    expect(find.text('开奖历史'), findsOneWidget);
    expect(api.calls, hasLength(2));
    expect(
        api.calls.every((call) =>
            call.query['machineCode'] == 'current-group-machine' &&
            call.headers['X-Group-Id'] == 'group-test'),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('SDK type updates show entry and remove an old open preview',
      (tester) async {
    seed(0);
    await tester.pumpWidget(chat());
    await tester.pumpAndSettle();
    expect(find.byKey(_handle), findsNothing);
    expect(find.text('开奖记录'), findsNothing);
    seed(3);
    await tester.pumpAndSettle();
    expect(find.byKey(_handle), findsOneWidget);
    expect(find.text('开奖记录'), findsOneWidget);
    await tester.tap(find.byKey(_handle));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lottery-preview-open')), findsOneWidget);
    seed(1);
    await tester.pumpAndSettle();
    expect(find.byKey(_handle), findsNothing);
    expect(find.text('开奖记录'), findsNothing);
    expect(find.byKey(const ValueKey('lottery-preview-open')), findsNothing);
    seed(2);
    await tester.pumpAndSettle();
    expect(find.byKey(_handle), findsNothing);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
