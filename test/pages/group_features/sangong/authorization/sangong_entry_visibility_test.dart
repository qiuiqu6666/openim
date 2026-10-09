import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_agent_floating_entry.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';
import '../sangong_test_support.dart';

const _groupID = 'group-sangong';
const _chatKey = ValueKey('ordinary-group-chat');

/// Uses the real account/group cache and authorization epochs. Only transport
/// responses and the independently verified account flag are replaced.
class _EntryFixture {
  _EntryFixture({bool privileged = true, int gameType = 1}) {
    api.privilege.setAllowed(privileged);
    api.respond = (call) {
      if (call.path.endsWith('/config')) {
        return {
          'active': true,
          'tenantId': _groupID,
          'imGroupGameId': _groupID,
          'name': '当前群的厅',
          'imGroupAdminStatsId': 'group-statistics',
          'imGroupLedgerId': 'group-credit',
          'imBotUserId': 'im_bot',
        };
      }
      if (call.path.endsWith('/feature-capabilities')) {
        if (capabilitiesUnavailable) {
          throw const GroupFeatureException('该功能的服务暂未开通',
              code: 'SERVICE_UNAVAILABLE', unavailable: true);
        }
        return {
          'groupID': _groupID,
          'capabilityVersion': capabilityVersion,
          'sangong': {
            'canConfigure': businessGranted,
            'canManage': businessGranted,
            'canOpenAgent': agentAssigned,
            'canViewRebateHistory': agentAssigned,
            'tenantID': agentAssigned
                ? 'tenant-authorized'
                : businessGranted
                    ? _groupID
                    : '',
          },
        };
      }
      return sangongFixtureResponse(call);
    };
    store = GroupFeatureStore(
      api: api,
      accountPrivilege: api.privilege,
      sessionCurrent: () => active,
      fetchGroups: (_) async => [],
    );
    store.seed(GroupInfo.fromJson({
      'groupID': _groupID,
      'groupName': '三公群聊',
      // A marked Sangong group may still have no legacy groupFeatures summary.
      'ex': '{"gameType":$gameType}',
    }));
  }

  final api = SangongTestApi();
  late final GroupFeatureStore store;
  bool active = true;
  bool capabilitiesUnavailable = true;
  bool businessGranted = false;
  bool agentAssigned = false;
  int capabilityVersion = 1;
  SangongRuntime? runtime;

  GroupFeatureContext get context => store.context(
        id: _groupID,
        name: '三公群聊',
        userID: 'owner',
        admin: false,
        current: () => active,
      );

  Iterable<SangongCall> get privateCalls => api.calls
      .where((call) => call.useBearerAuth && !call.path.endsWith('/config'));

  Future<void> dispose() async {
    active = false;
    store.dispose();
    await api.closeStreams();
    api.privilege.dispose();
  }
}

Future<void> _pumpChat(WidgetTester tester, _EntryFixture fixture,
    {bool dark = false}) async {
  await fixture.store.loadCapabilities(_groupID);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        colorSchemeSeed: const Color(0xff0089ff),
      ),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: fixture.store,
          builder: (context, _) => SangongFeatureHost(
            featureContext: fixture.context,
            builder: (context, status, overlay) {
              fixture.runtime = SangongScope.read(context);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Column(children: [
                      status,
                      const Expanded(
                        child: Center(child: Text('普通聊天', key: _chatKey)),
                      ),
                    ]),
                  ),
                  overlay,
                ],
              );
            },
          ),
        ),
      ),
    ),
  ));
  await flushSangong(tester);
}

Future<void> _flushRoute(WidgetTester tester) async {
  await flushSangong(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await flushSangong(tester);
}

List<String> _toolboxLabels(WidgetTester tester, _EntryFixture fixture) =>
    GroupFeatureActions.items(
            tester.element(find.byKey(_chatKey)), fixture.context)
        .map((item) => item.text)
        .toList();

void _openToolbox(WidgetTester tester, _EntryFixture fixture, String label) {
  GroupFeatureActions.items(
          tester.element(find.byKey(_chatKey)), fixture.context)
      .firstWhere((item) => item.text == label)
      .onTap!();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
  });

  for (final dark in [false, true]) {
    testWidgets(
        'assigned ordinary member opens agent module from chat dark=$dark',
        (tester) async {
      final fixture = _EntryFixture(privileged: false, gameType: 4)
        ..capabilitiesUnavailable = false
        ..agentAssigned = true;
      fixture.store.seed(GroupInfo(
          groupID: _groupID,
          ex: jsonEncode({
            'gameType': 4,
            'groupFeatures': {
              'schemaVersion': 1,
              'revision': 1,
              'games': {
                'sangong': {
                  'enabled': true,
                  'agentEntry': true,
                  'rebateHistoryEntry': true,
                }
              }
            }
          })));
      addTearDown(fixture.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pumpChat(tester, fixture, dark: dark);
      expect(_toolboxLabels(tester, fixture), ['三公代理']);
      expect(find.byType(SangongAgentFloatingEntry), findsOneWidget);
      _openToolbox(tester, fixture, '三公代理');
      await _flushRoute(tester);
      expect(find.byType(SangongAgentDashboardPage), findsOneWidget);
      expect(find.text('团队概览'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(fixture.api.calls.where((c) => c.path.contains('/api/v2/groups/')),
          isEmpty);
      expect(
          fixture.api.calls
              .where((c) => c.path.contains('/api/v2/agent-groups/')),
          isNotEmpty,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join('|'));

      fixture.agentAssigned = false;
      fixture.capabilityVersion++;
      await fixture.store.loadCapabilities(_groupID, force: true);
      await _flushRoute(tester);
      expect(find.byType(SangongAgentDashboardPage), findsNothing);
      expect(find.byType(SangongAgentFloatingEntry), findsNothing);
      expect(_toolboxLabels(tester, fixture), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'privileged member without assigned-agent capabilities keeps only management entry, dark=$dark',
        (tester) async {
      final fixture = _EntryFixture(gameType: 4);
      addTearDown(fixture.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pumpChat(tester, fixture, dark: dark);

      expect(fixture.context.isGroupAdmin, isFalse);
      expect(fixture.context.features.valid, isFalse);
      expect(fixture.context.capabilities.sangong.canManage, isFalse);
      expect(_toolboxLabels(tester, fixture), ['三公运营']);
      expect(find.byType(GroupGameFloatingEntry), findsNothing);
      expect(find.byType(SangongAgentFloatingEntry), findsNothing);
      expect(fixture.privateCalls, isEmpty);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);

      // An explicit management entry still owns its retryable error route.
      _openToolbox(tester, fixture, '三公运营');
      await _flushRoute(tester);
      expect(find.text('三公管理'), findsOneWidget);
      expect(find.text('该功能的服务暂未开通'), findsWidgets);
      expect(find.text('重试'), findsOneWidget);
      expect(fixture.privateCalls, isEmpty);
      expect(navigator.canPop(), isTrue);
      navigator.pop();
      await _flushRoute(tester);

      // Direct agent navigation also needs the verified personal capability.
      await SangongModule.openAgent(tester.element(find.byKey(_chatKey)),
          featureContext: fixture.context, runtime: fixture.runtime);
      await _flushRoute(tester);
      expect(navigator.canPop(), isFalse);
      expect(fixture.privateCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'account grant reveals public entries but still needs group permission',
      (tester) async {
    final fixture = _EntryFixture(privileged: false, gameType: 4);
    addTearDown(fixture.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpChat(tester, fixture);
    expect(_toolboxLabels(tester, fixture), isEmpty);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byType(SangongAgentFloatingEntry), findsNothing);

    fixture.api.privilege.setAllowed(true);
    await fixture.api.privilege.refresh();
    await flushSangong(tester);
    expect(_toolboxLabels(tester, fixture), ['三公运营']);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byType(SangongAgentFloatingEntry), findsNothing);

    fixture.api.privilege.setAllowed(false);
    await flushSangong(tester);
    expect(_toolboxLabels(tester, fixture), isEmpty);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byType(SangongAgentFloatingEntry), findsNothing);
    expect(fixture.privateCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'visible toolbox reports denied business access without a private read',
      (tester) async {
    final fixture = _EntryFixture()..capabilitiesUnavailable = false;
    addTearDown(fixture.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpChat(tester, fixture);
    _openToolbox(tester, fixture, '三公运营');
    await _flushRoute(tester);
    expect(find.text('三公管理'), findsOneWidget);
    expect(find.text(fixture.runtime!.manageUnavailableReason!), findsWidgets);
    expect(find.text('重试'), findsOneWidget);
    expect(fixture.privateCalls, isEmpty);
    expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'public module survives permission epoch changes and retries into real business access',
      (tester) async {
    final fixture = _EntryFixture()..capabilitiesUnavailable = false;
    addTearDown(fixture.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpChat(tester, fixture);
    final beforeEntry = fixture.context;
    fixture.capabilityVersion = 2;
    _openToolbox(tester, fixture, '三公运营');
    await _flushRoute(tester);

    expect(beforeEntry.capabilitiesCurrent(), isFalse);
    expect(find.text('三公管理'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isTrue);
    expect(fixture.privateCalls, isEmpty);

    fixture.capabilitiesUnavailable = true;
    // The public route owns its retry's loading/error transition. An external
    // epoch change still closes a captured private page, tested separately.
    await tester.tap(find.text('重试'));
    await _flushRoute(tester);
    expect(find.text('该功能的服务暂未开通'), findsOneWidget);
    expect(navigator.canPop(), isTrue);
    expect(fixture.privateCalls, isEmpty);

    fixture.capabilitiesUnavailable = false;
    fixture.businessGranted = true;
    fixture.capabilityVersion = 3;
    fixture.store.apply(_groupID, {
      'schemaVersion': 1,
      'revision': 1,
      'games': {
        'sangong': {'enabled': true, 'manageEntry': true},
      },
    });
    await tester.tap(find.text('重试'));
    await _flushRoute(tester);
    expect(find.byType(SangongManageHomePage), findsOneWidget);
    expect(find.text('游戏规则'), findsOneWidget);
    expect(find.text('该功能的服务暂未开通'), findsNothing);
    expect(navigator.canPop(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private route guard keeps its default capability epoch fence',
      (tester) async {
    final fixture = _EntryFixture()..capabilitiesUnavailable = false;
    addTearDown(fixture.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpChat(tester, fixture);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final route = navigator.push<void>(SangongPageRoute(
      context: tester.element(find.byKey(_chatKey)),
      builder: (_) => const Scaffold(body: Text('受保护的私密数据')),
    ));
    await _flushRoute(tester);
    expect(find.text('受保护的私密数据'), findsOneWidget);
    fixture.store.invalidateCapabilities(_groupID);
    await _flushRoute(tester);
    await route;
    expect(find.text('受保护的私密数据', skipOffstage: false), findsNothing);
    expect(find.byKey(_chatKey), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    expect(fixture.privateCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
