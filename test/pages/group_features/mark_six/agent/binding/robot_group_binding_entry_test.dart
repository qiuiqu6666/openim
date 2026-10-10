import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_descendants_page.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_feature_host.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../support/performance/render_test_fakes.dart';
import '../../mark_six_fixtures.dart';

const _groupID = 'group-test';
const _robotPath = '/me/robot/groups/$_groupID';

Map<String, dynamic> _binding(
        {String groupID = _groupID, bool bound = true, bool enabled = true}) =>
    {
      'groupId': groupID,
      'bound': bound,
      'enabled': enabled,
      'machineCodeMasked': '***test',
    };

GroupFeatureContext _context(MarkSixFakeApi api,
        {String groupID = _groupID,
        String userID = 'self',
        GroupGameType type = GroupGameType.markSixAgent,
        bool legacyFlags = false,
        bool canAgent = false,
        bool canHistory = false,
        int version = 1,
        bool Function()? sessionCurrent,
        bool Function()? capabilitiesCurrent}) =>
    GroupFeatureContext(
      groupID: groupID,
      groupName: '测试代理群',
      currentUserID: userID,
      api: api,
      gameType: type,
      sessionCurrent: sessionCurrent ?? () => true,
      capabilitiesCurrent: capabilitiesCurrent ?? () => true,
      onFeaturesChanged: (_) {},
      features: GroupFeatures(
        revision: version,
        valid: true,
        markSix: GroupGameFeature(
          enabled: legacyFlags,
          agentEntry: legacyFlags,
          rebateHistoryEntry: legacyFlags,
        ),
      ),
      capabilities: GroupFeatureCapabilities(
        version: version,
        markSix: GroupGameCapabilities(
          canOpenAgent: canAgent,
          canViewRebateHistory: canHistory,
        ),
      ),
    );

Widget _host(GroupFeatureContext context,
        {Brightness brightness = Brightness.light}) =>
    renderTestHost(
      Builder(
        builder: (contextForToast) => EasyLoading.init()(
          contextForToast,
          MarkSixFeatureHost(
            featureContext: context,
            builder: (_, __, overlay) => Stack(children: [
              const Positioned.fill(child: Text('实际聊天内容')),
              overlay,
            ]),
          ),
        ),
      ),
      brightness: brightness,
    );

Future<void> _mount(WidgetTester tester, GroupFeatureContext context,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(_host(context, brightness: brightness));
  await tester.pumpAndSettle();
}

void _expectActions({required bool agent, required bool history}) {
  expect(find.text('查'), agent ? findsOneWidget : findsNothing);
  expect(find.text('反'), agent ? findsOneWidget : findsNothing);
  expect(find.text('历'), history ? findsOneWidget : findsNothing);
}

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => Get.reset());

  for (final brightness in Brightness.values) {
    testWidgets(
        'bound type 2 ignores legacy flags and opens real descendants / $brightness',
        (tester) async {
      final api = MarkSixFakeApi(
          respond: (_, path, query, __) => path == _robotPath
              ? _binding()
              : markSixFixtureResponse(path, query));
      await _mount(tester, _context(api, canAgent: true, canHistory: true),
          brightness: brightness);
      expect(find.text('显'), findsOneWidget);
      expect(api.calls, hasLength(1));
      final bindingCall = api.calls.single;
      expect(bindingCall.method, 'GET');
      expect(bindingCall.path, _robotPath);
      expect(bindingCall.query, isEmpty);
      expect(bindingCall.headers, isEmpty);
      expect(bindingCall.useBearerAuth, isTrue);

      await tester.tap(find.text('显'));
      await tester.pumpAndSettle();
      _expectActions(agent: true, history: true);
      await tester.tap(find.text('查'));
      await tester.pumpAndSettle();
      expect(find.byType(AgentDescendantsPage), findsOneWidget);
      expect(find.text('我的下级'), findsOneWidget);
      expect(api.calls, hasLength(2));
      expect(api.calls.last.path, '/me/agent/descendants');
      expect(api.calls.last.headers['X-Group-Id'], _groupID);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets(
      'unbound type 2 stays hidden with all legacy flags and permissions',
      (tester) async {
    final api =
        MarkSixFakeApi(respond: (_, __, ___, ____) => _binding(bound: false));
    await _mount(tester,
        _context(api, legacyFlags: true, canAgent: true, canHistory: true));
    expect(find.text('显'), findsNothing);
    _expectActions(agent: false, history: false);
    expect(api.calls.single.path, _robotPath);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bound but disabled robot still exposes permitted actions',
      (tester) async {
    final api =
        MarkSixFakeApi(respond: (_, __, ___, ____) => _binding(enabled: false));
    await _mount(tester, _context(api, canAgent: true, canHistory: true));
    expect(find.text('显'), findsOneWidget);
    await tester.tap(find.text('显'));
    await tester.pumpAndSettle();
    _expectActions(agent: true, history: true);
    expect(api.calls.single.path, _robotPath);
  });

  for (final wrongGroup in [true, false]) {
    testWidgets(
        '${wrongGroup ? 'wrong group' : 'failed binding read'} never exposes type 2',
        (tester) async {
      final api = MarkSixFakeApi(respond: (_, __, ___, ____) {
        if (!wrongGroup) throw StateError('binding unavailable');
        return _binding(groupID: 'another-group');
      });
      await _mount(tester,
          _context(api, legacyFlags: true, canAgent: true, canHistory: true));
      expect(find.text('显'), findsNothing);
      _expectActions(agent: false, history: false);
      expect(api.calls.single.path, _robotPath);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capability and feature updates share the pending binding read',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(respond: (_, __, ___, ____) => pending.future);
    await _mount(tester, _context(api));
    expect(find.text('显'), findsNothing);
    await _mount(
        tester, _context(api, canAgent: true, legacyFlags: true, version: 2));
    await _mount(tester, _context(api, canAgent: true, version: 3));
    expect(api.calls, hasLength(1));

    pending.complete(_binding());
    await tester.pumpAndSettle();
    expect(find.text('显'), findsOneWidget);
    await tester.tap(find.text('显'));
    await tester.pumpAndSettle();
    _expectActions(agent: true, history: false);

    await _mount(tester, _context(api, canHistory: true, version: 4));
    _expectActions(agent: false, history: true);
    expect(find.text('隐'), findsOneWidget);
    expect(api.calls, hasLength(1));
    await _mount(
        tester, _context(api, canAgent: true, canHistory: true, version: 5));
    _expectActions(agent: true, history: true);
    expect(api.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final capabilitiesValid in [true, false]) {
    testWidgets(
        'bound type 2 without effective permissions toasts and stays collapsed / valid=$capabilitiesValid',
        (tester) async {
      final api = MarkSixFakeApi(respond: (_, __, ___, ____) => _binding());
      await _mount(
          tester,
          _context(api,
              canAgent: !capabilitiesValid,
              canHistory: !capabilitiesValid,
              capabilitiesCurrent: () => capabilitiesValid));
      expect(find.text('显'), findsOneWidget);
      await tester.tap(find.text('显'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('暂无代理功能权限'), findsOneWidget);
      expect(find.text('显'), findsOneWidget);
      expect(find.text('隐'), findsNothing);
      _expectActions(agent: false, history: false);
      expect(api.calls.single.path, _robotPath);
      await EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in [
    'group',
    'account',
    'api',
    'type',
    'session',
    'dispose'
  ]) {
    testWidgets(
        'late binding response cannot revive entry after $change change',
        (tester) async {
      final oldRead = Completer<Map<String, dynamic>>();
      var oldSessionCurrent = true;
      var reads = 0;
      final oldApi = MarkSixFakeApi(respond: (_, path, __, ___) {
        if (reads++ == 0) return oldRead.future;
        return _binding(
            groupID: Uri.decodeComponent(path.split('/').last), bound: false);
      });
      final nextApi =
          MarkSixFakeApi(respond: (_, __, ___, ____) => _binding(bound: false));
      await _mount(
          tester, _context(oldApi, sessionCurrent: () => oldSessionCurrent));
      expect(oldApi.calls, hasLength(1));
      if (change == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } else {
        if (change == 'session') oldSessionCurrent = false;
        await _mount(
            tester,
            _context(change == 'api' ? nextApi : oldApi,
                groupID: change == 'group' ? 'next-group' : _groupID,
                userID: change == 'account' ? 'next-user' : 'self',
                type: change == 'type'
                    ? GroupGameType.markSix
                    : GroupGameType.markSixAgent));
        expect(find.text('显'), findsNothing);
        final totalReads = oldApi.calls.length + nextApi.calls.length;
        expect(totalReads, change == 'type' ? 1 : 2);
        if (change == 'group') {
          expect(oldApi.calls.last.path, '/me/robot/groups/next-group');
        }
      }
      oldRead.complete(_binding());
      await tester.pumpAndSettle();
      expect(find.text('显'), findsNothing);
      _expectActions(agent: false, history: false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('expired session cannot expose a completed binding',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    var current = true;
    final api = MarkSixFakeApi(respond: (_, __, ___, ____) => pending.future);
    final context = _context(api, sessionCurrent: () => current);
    await _mount(tester, context);
    current = false;
    pending.complete(_binding());
    await _mount(tester, context);
    expect(find.text('显'), findsNothing);
    expect(api.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final legacyFlags in [false, true]) {
    testWidgets('other game types retain legacy gating / flags=$legacyFlags',
        (tester) async {
      final api = MarkSixFakeApi();
      for (final type in GroupGameType.values
          .where((value) => value != GroupGameType.markSixAgent)) {
        await _mount(
            tester,
            _context(api,
                type: type,
                legacyFlags: legacyFlags,
                canAgent: true,
                canHistory: true));
        expect(find.text('显'), legacyFlags ? findsOneWidget : findsNothing,
            reason: type.name);
        expect(api.calls, isEmpty, reason: type.name);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
