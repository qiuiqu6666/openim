import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/mark_six/pages/mark_six_page.dart';
import 'package:openim/pages/group_features/bingo/bingo_page.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_latest_card.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_feature_host.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';

import '../../../support/account_privilege_fixture.dart';
import '../../../support/performance/render_test_fakes.dart';
import 'mark_six_fixtures.dart';

const _handle = ValueKey('lottery-edge-handle');

final bingoPreviewDraw = BingoDraw(
  issue: '197',
  drawTime: DateTime(2026, 10, 22, 17, 45, 45),
  closeTime: DateTime(2026, 10, 22, 17, 46),
  special: const BingoBall(44, '猪', Colors.red),
  regular: const [
    BingoBall(3, '鼠', Colors.blue),
    BingoBall(11, '马', Colors.green),
    BingoBall(19, '蛇', Colors.red),
    BingoBall(26, '龙', Colors.orange),
    BingoBall(32, '兔', Colors.purple),
    BingoBall(38, '鸡', Colors.blue)
  ],
);

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
        await tester.tap(find.text('点击卡片 · 全屏查看开奖记录'));
      } else {
        await tester.tap(find.text('开奖记录'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MarkSixPage), findsOneWidget);
      expect(find.text('京东微信红包'), findsOneWidget);
      expect(find.textContaining('本群尚未配置六合彩机器码'), findsNothing);
      expect(find.text('开奖历史'), findsOneWidget);
      expect(find.text('本群尚未开放六合彩'), findsNothing);
      expect(api.calls, hasLength(2));
      expect(
          api.calls.every((call) =>
              call.query['machineCode'] == 'GZKH-DJ3M-VKSB' &&
              call.headers['X-Group-Id'] == 'group-test'),
          isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets(
      'type 5 opens an independent Bingo page without Mark Six requests',
      (tester) async {
    seed(5);
    await tester.pumpWidget(chat());
    await tester.pumpAndSettle();
    expect(find.byKey(_handle), findsOneWidget);
    expect(find.text('宾果开奖记录'), findsOneWidget);
    await tester.tap(find.byKey(_handle));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bingo-latest-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('bingo-preview-open')), findsOneWidget);
    expect(find.text('第 — 期'), findsOneWidget);
    expect(find.text('第 197 期'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bingo-preview-open')));
    await tester.pumpAndSettle();
    expect(find.byType(BingoPage), findsOneWidget);
    expect(find.byKey(const ValueKey('bingo-latest-card')), findsOneWidget);
    expect(find.text('台湾宾果六合彩'), findsOneWidget);
    for (final tab in {
      '智能预测': '暂无预测数据',
      '已开统计': '开奖记录加载失败，请重试',
      '游戏规则': '开奖号码',
      '开奖历史': '开奖记录加载失败，请重试',
    }.entries) {
      await tester.tap(find.text(tab.key));
      await tester.pumpAndSettle();
      expect(find.text(tab.value), findsOneWidget);
      expect(find.byKey(const ValueKey('bingo-latest-card')), findsOneWidget);
    }
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Bingo card lays out one special and six regular balls',
      (tester) async {
    final draw = BingoDraw(
      issue: '197',
      drawTime: DateTime(2026, 10, 22, 17, 45, 45),
      closeTime: DateTime(2026, 10, 22, 17, 46),
      special: const BingoBall(44, '猪', Colors.red),
      regular: const [
        BingoBall(3, '鼠', Colors.blue),
        BingoBall(11, '马', Colors.green),
        BingoBall(19, '蛇', Colors.red),
        BingoBall(26, '龙', Colors.orange),
        BingoBall(32, '兔', Colors.purple),
        BingoBall(38, '鸡', Colors.blue),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BingoLatestCard(draw: draw)),
    ));
    expect(find.text('第 198 期'), findsOneWidget);
    expect(draw.issue, '197');
    expect(find.text('44'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Bingo balls retain visible size after layout scaling',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 330,
            child: BingoLatestCard(draw: bingoPreviewDraw, preview: true),
          )),
    )));
    final balls = find.byType(MarkSixNumberBall);
    double displayedWidth(int index) {
      final box = tester.renderObject<RenderBox>(balls.at(index));
      return (box.localToGlobal(Offset(box.size.width, 0)) -
              box.localToGlobal(Offset.zero))
          .distance;
    }

    expect(displayedWidth(6), inInclusiveRange(42, 44));
    expect(displayedWidth(0), inInclusiveRange(32, 33));
    expect(tester.getCenter( balls.at(0)).dx,
        lessThan(tester.getCenter(balls.at(6)).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bingo preview closes when the group type changes',
      (tester) async {
    seed(5);
    await tester.pumpWidget(chat());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_handle));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bingo-latest-preview')), findsOneWidget);
    seed(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bingo-latest-preview')), findsNothing);
    expect(find.byKey(_handle), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('Bingo draw entry is hidden in other new game types',
      (tester) async {
    for (final type in [6, 7, 8]) {
      seed(type);
      await tester.pumpWidget(chat());
      await tester.pumpAndSettle();
      expect(find.byKey(_handle), findsNothing);
      expect(find.text('开奖记录'), findsNothing);
    }
    expect(api.calls, isEmpty);
  });

  testWidgets('type 3 uses fixed machine despite group binding and flags off',
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
            call.query['machineCode'] == 'GZKH-DJ3M-VKSB' &&
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
    expect(api.calls, hasLength(3));
    final bindingCalls =
        api.calls.where((call) => call.path == '/me/robot/groups/group-test');
    expect(bindingCalls, hasLength(1));
    expect(bindingCalls.single.headers, isEmpty);
    expect(bindingCalls.single.useBearerAuth, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
