import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/services/group_game_prefs.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_agent_floating_entry.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';

import '../sangong_test_support.dart';

const _groupID = 'group-game-type';
const _summary = {
  'schemaVersion': 1,
  'revision': 5,
  'games': {
    'sangong': {'enabled': true, 'manageEntry': true, 'agentEntry': true}
  }
};
const _unrelated = {
  'announcementStyle': 'keep-original',
  'nested': {
    'values': [3, 'unchanged']
  }
};

String _ex(dynamic type, {bool includeType = true}) => jsonEncode({
      if (includeType) 'gameType': type,
      'groupFeatures': _summary,
      'unrelated': _unrelated,
    });

class _Fixture {
  _Fixture(String ex, {bool privileged = true}) {
    api.privilege.setAllowed(privileged);
    api.respond = (call) {
      if (call.path.endsWith('/config')) {
        throw const GroupFeatureException('当前群未配置三公',
            code: 'SERVICE_UNAVAILABLE',
            statusCode: 404,
            serverCode: 'TENANT_NOT_FOUND');
      }
      return sangongFixtureResponse(call);
    };
    store = GroupFeatureStore(
        api: api,
        accountPrivilege: api.privilege,
        sessionCurrent: () => active,
        fetchGroups: (_) async => []);
    seed(ex);
  }

  final api = SangongTestApi();
  late final GroupFeatureStore store;
  SangongRuntime? runtime;
  bool active = true;
  Iterable<SangongCall> get businessCalls =>
      api.calls.where((call) => !call.path.endsWith('/config'));

  String get preferenceKey => '${api.baseUrl}:owner:$_groupID';
  GroupFeatureContext get context => store.context(
      id: _groupID,
      name: '群类型显示测试',
      userID: 'owner',
      admin: false,
      current: () => active);

  void seed(String ex) =>
      store.seed(GroupInfo(groupID: _groupID, groupName: '群类型显示测试', ex: ex));

  Future<void> dispose() async {
    active = false;
    store.dispose();
    await api.closeStreams();
    api.privilege.dispose();
  }
}

Future<void> _pumpChat(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: fixture.store,
                  builder: (_, __) => SangongFeatureHost(
                      featureContext: fixture.context,
                      builder: (context, status, overlay) {
                        fixture.runtime = SangongScope.read(context);
                        return Stack(fit: StackFit.expand, children: [
                          const Positioned.fill(
                              child: Center(child: Text('群聊正文'))),
                          overlay,
                        ]);
                      }))))));
  await flushSangong(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
  });

  for (final (label, ex, visible, agentVisible) in [
    ('ordinary', _ex(0), false, false),
    ('sangong', _ex(1), true, false),
    ('numeric 1.0', _ex(1.0), true, false),
    ('mark six agent', _ex(2), false, false),
    ('mark six draw', _ex(3), false, false),
    ('sangong agent', _ex(4), false, true),
    ('numeric 4.0', _ex(4.0), false, true),
    ('missing type', _ex(null, includeType: false), false, false),
    ('invalid JSON', 'not-json', false, false),
    ('string type', _ex('1'), false, false),
    ('string agent type', _ex('4'), false, false),
    ('unknown type', _ex(7), false, false),
  ]) {
    testWidgets('operator and agent entries follow top-level $label',
        (tester) async {
      final fixture = _Fixture(ex);
      addTearDown(fixture.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pumpChat(tester, fixture);

      expect(find.byType(GroupGameFloatingEntry),
          visible ? findsOneWidget : findsNothing);
      expect(find.byType(SangongAgentFloatingEntry),
          agentVisible ? findsOneWidget : findsNothing);
      final labels = GroupFeatureActions.items(
              tester.element(find.text('群聊正文')), fixture.context)
          .map((item) => item.text);
      expect(labels.contains('三公代理'), agentVisible);
      expect(fixture.store.cachedGroupInfo(_groupID)?.ex, ex);
      expect(fixture.businessCalls, isEmpty);
      expect(fixture.api.calls.where((c) => c.path.endsWith('/config')).length,
          visible ? 1 : 0);
      expect(fixture.api.streamStarts, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'same-summary type updates hide and restore the operator in place',
      (tester) async {
    final fixture = _Fixture(_ex(1));
    addTearDown(fixture.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpChat(tester, fixture);
    expect(find.byType(GroupGameFloatingEntry), findsOneWidget);
    final originalRuntime = fixture.runtime;
    final originalContext = fixture.context;

    final markSixEx = _ex(2);
    fixture.seed(markSixEx);
    await tester.pump();
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byType(SangongAgentFloatingEntry), findsNothing);
    expect(fixture.store.cachedGroupInfo(_groupID)?.ex, markSixEx);
    expect(fixture.store.features(_groupID).revision, 5);
    expect(originalContext.capabilitiesCurrent(), isTrue);

    fixture.seed(_ex(4));
    await flushSangong(tester);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byType(SangongAgentFloatingEntry), findsOneWidget);
    expect(
        GroupFeatureActions.items(
                tester.element(find.text('群聊正文')), fixture.context)
            .any((item) => item.text == '三公代理'),
        isTrue);

    final sangongEx = _ex(1);
    fixture.seed(sangongEx);
    await flushSangong(tester);
    expect(find.byType(GroupGameFloatingEntry), findsOneWidget);
    expect(find.byType(SangongAgentFloatingEntry), findsNothing);
    expect(
        GroupFeatureActions.items(
                tester.element(find.text('群聊正文')), fixture.context)
            .any((item) => item.text == '三公代理'),
        isFalse);
    expect(identical(fixture.runtime, originalRuntime), isTrue);
    expect(fixture.store.features(_groupID).revision, 5);
    expect(
        jsonDecode(fixture.store.cachedGroupInfo(_groupID)!.ex!)['unrelated'],
        _unrelated);
    expect(fixture.businessCalls, isEmpty);
    expect(fixture.api.streamStarts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sangong type does not bypass account or business permissions',
      (tester) async {
    final fixture = _Fixture(_ex(1), privileged: false);
    addTearDown(fixture.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpChat(tester, fixture);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);

    fixture.api.privilege.setAllowed(true);
    await flushSangong(tester);
    expect(find.byType(GroupGameFloatingEntry), findsOneWidget);
    final runtime = fixture.runtime!;
    expect(runtime.canConfigure, isFalse);
    expect(runtime.canManage, isFalse);
    expect(runtime.http.hasTenant, isFalse);
    expect(runtime.canInitialize, isFalse);
    await rejectSangongRequest(
        tester, runtime.admin.fetchSession(), isA<Exception>());
    expect(fixture.businessCalls, isEmpty);
    expect(fixture.api.streamStarts, 0);

    fixture.api.privilege.setAllowed(false);
    await flushSangong(tester);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stored hidden preference survives group-type updates',
      (tester) async {
    final fixture = _Fixture(_ex(1));
    addTearDown(fixture.dispose);
    addTearDown(() => unmountSangong(tester));
    await GroupGamePrefs.instance.setFloatVisible(fixture.preferenceKey, false);
    await _pumpChat(tester, fixture);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);

    fixture.seed(_ex(2));
    await tester.pump();
    fixture.seed(_ex(1));
    await tester.pump();
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byType(SangongAgentFloatingEntry), findsNothing);
    expect(await GroupGamePrefs.instance.isFloatVisible(fixture.preferenceKey),
        isFalse);
    expect(tester.takeException(), isNull);
  });
}
