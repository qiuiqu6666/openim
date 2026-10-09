import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_game_type.dart';
import 'package:openim/pages/group_features/sangong/agents/user_group/sangong_user_agent_group_entry.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_v2_api.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';
import '../../sangong_test_support.dart';

void main() {
  testWidgets(
      'assigned ordinary user sees own agent entry and cannot use management',
      (tester) async {
    final api = SangongTestApi()..privilege.setAllowed(false);
    final context = sangongTestContext(api,
        gameType: GroupGameType.sangongAgent,
        canConfigure: false,
        canManage: false,
        manageEntry: false);
    final runtime = sangongTestRuntime(context);
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    expect(runtime.canOpenAgent, isTrue);
    expect(runtime.canManage, isFalse);
    expect(runtime.http.canCallAdmin, isFalse);
    await pumpSangongPage(tester, runtime, const Scaffold(body: Text('群聊')));
    final pageContext = tester.element(find.text('群聊'));
    final actions = GroupFeatureActions.items(pageContext, context)
        .map((item) => item.text);
    expect(actions, contains('三公代理'));
    expect(actions, isNot(contains('三公运营')));
    final agent = SangongV2Api(runtime.http, agent: true);
    await completeSangongRequest(tester, agent.read('context'));
    await rejectSangongRequest(
        tester, SangongV2Api(runtime.http).read('users'), isA<DioException>());
    unawaited(SangongAgentDashboardPage.open(pageContext));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SangongAgentDashboardPage), findsOneWidget);
    expect(api.calls.where((c) => c.path.contains('/api/v2/agent-groups/')),
        isNotEmpty);
    expect(api.calls.where((c) => c.path.contains('/api/v2/groups/')), isEmpty);
    runtime.updateContext(sangongTestContext(api,
        gameType: GroupGameType.sangongAgent,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false,
        canViewHistory: false,
        capabilityVersion: 2));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SangongAgentDashboardPage), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'manager assigns and clears a user group with real names dark=$dark',
        (tester) async {
      String? assigned;
      final api = SangongTestApi();
      api.respond = (call) {
        if (call.path.endsWith('/agent-groups')) {
          return {'gameGroupId': 'group-sangong', 'agentGroupIds': <String>[]};
        }
        if (call.method == 'POST') {
          expect(call.path, endsWith('/commands/user.agent_group'));
          final input = call.body!['input'] as Map;
          expect(input.containsKey('bindIfNeeded'), isFalse);
          assigned = input['agentGroupId'] == ''
              ? null
              : input['agentGroupId'] as String;
          return {
            'ok': true,
            'requestId': call.body!['requestId'],
            'data': {
              'imUserId': 'player',
              'gameGroupId': 'group-sangong',
              'agentGroupId': assigned
            }
          };
        }
        return {
          'imUserId': 'player',
          'gameGroupId': 'group-sangong',
          'agentGroupId': assigned
        };
      };
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(
          tester,
          runtime,
          Scaffold(
              body: SangongUserAgentGroupEntry(
                  imUserId: 'player',
                  hasRebate: true,
                  fetchGroups: (_) async => [
                        GroupInfo(
                            groupID: 'group_@agents-A', groupName: '秋的代理群')
                      ])),
          dark: dark,
          platform: dark ? TargetPlatform.iOS : TargetPlatform.android);
      await flushSangong(tester);
      expect(find.text('未设置'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('请输入群 ID'), findsOneWidget);
      await tester.enterText(
          find.byType(CupertinoTextField), '  group_@agents-A  ');
      await tester.tap(find.text('保存'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(assigned, 'group_@agents-A');
      expect(find.text('秋的代理群\n群 ID：group_@agents-A'), findsOneWidget);
      await tester.tap(find.text('更换'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CupertinoTextField>(find.byType(CupertinoTextField))
              .controller!
              .text,
          'group_@agents-A');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除绑定'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('确定'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(assigned, isNull);
      expect(api.calls.where((c) => c.path.endsWith('/agent-groups')), isEmpty);
      expect(api.calls.where((c) => c.method == 'POST'), hasLength(2));
      expect(find.text('未设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final exactMatch in [false, true]) {
    testWidgets(
        'IM confirms displayed @ ID without changing exact IDs: $exactMatch',
        (tester) async {
      String? assigned;
      final api = SangongTestApi()
        ..respond = (call) {
          if (call.method == 'POST') {
            assigned = (call.body!['input'] as Map)['agentGroupId'] as String;
            return {
              'ok': true,
              'requestId': call.body!['requestId'],
              'data': {
                'imUserId': 'player',
                'gameGroupId': 'group-sangong',
                'agentGroupId': assigned,
              }
            };
          }
          return {
            'imUserId': 'player',
            'gameGroupId': 'group-sangong',
            'agentGroupId': assigned
          };
        };
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(
          tester,
          runtime,
          Scaffold(
              body: SangongUserAgentGroupEntry(
                  imUserId: 'player',
                  hasRebate: true,
                  fetchGroups: (_) async => [
                        GroupInfo(groupID: 'room'),
                        if (exactMatch) GroupInfo(groupID: '@room'),
                      ])));
      await flushSangong(tester);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '@room');
      await tester.tap(find.text('保存'));
      await flushSangong(tester);
      expect(assigned, exactMatch ? '@room' : 'room');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('open ID prompt stops saving when management permission changes',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'imUserId': 'player',
            'gameGroupId': 'group-sangong',
            'agentGroupId': null,
          };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        const Scaffold(
            body: SangongUserAgentGroupEntry(
                imUserId: 'player', hasRebate: true)));
    await flushSangong(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'agent-room');
    runtime.updateContext(sangongTestContext(api,
        canManage: false, canConfigure: false, capabilityVersion: 2));
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsNothing);
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save preserves binding and zero rebate disables setting',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.method == 'POST') {
          throw DioException(
              requestOptions: RequestOptions(path: call.path),
              type: DioExceptionType.badResponse,
              response: Response(
                  requestOptions: RequestOptions(path: call.path),
                  statusCode: 409,
                  data: {
                    'code': 'AGENT_USER_GROUP_ALREADY_BOUND',
                    'message': '该用户在此群已绑定其他厅'
                  }));
        }
        return {
          'imUserId': 'player',
          'gameGroupId': 'group-sangong',
          'agentGroupId': 'existing'
        };
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    Widget page(bool hasRebate) => Scaffold(
        body: SangongUserAgentGroupEntry(
            imUserId: 'player',
            hasRebate: hasRebate,
            fetchGroups: (_) async => []));
    await pumpSangongPage(tester, runtime, page(true));
    await flushSangong(tester);
    await tester.tap(find.text('更换'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'conflicting-room');
    await tester.tap(find.text('保存'));
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('群 ID：existing'), findsOneWidget);
    expect(find.textContaining('群 ID：conflicting-room'), findsNothing);
    await pumpSangongPage(tester, runtime, page(false));
    await flushSangong(tester);
    final button =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '更换'));
    expect(button.onPressed, isNull);
    expect(find.text('清除绑定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late assignment query is hidden after group scope changes',
      (tester) async {
    final response = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => response.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        Scaffold(
            body: SangongUserAgentGroupEntry(
                imUserId: 'player',
                hasRebate: true,
                fetchGroups: (_) async =>
                    [GroupInfo(groupID: 'secret', groupName: '旧群私密资料')])));
    runtime.http.setTenantId('other');
    response.complete({
      'imUserId': 'player',
      'gameGroupId': 'group-sangong',
      'agentGroupId': 'secret'
    });
    await flushSangong(tester);
    expect(find.text('旧群私密资料'), findsNothing);
    expect(find.text('设置'), findsNothing);
  });
}
