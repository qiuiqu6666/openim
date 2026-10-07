import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_agent_floating_entry.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sangong_test_support.dart';

const _chatKey = ValueKey('current-tenant-chat');
String _tenantPath(String groupID) =>
    '/sangong/api/v2/groups/${Uri.encodeComponent(groupID)}/config';

class _Fixture {
  _Fixture({
    this.groupID = '@current-group',
    this.gameType = 1,
    this.admin = true,
    this.canConfigure = true,
    this.canManage = true,
    this.agentOnly = false,
    this.enabled = true,
    this.manageEntry = true,
    this.includeSummary = true,
    bool privileged = true,
  }) {
    api.privilege.setAllowed(privileged);
    api.respond = _respond;
    store = GroupFeatureStore(
        api: api,
        accountPrivilege: api.privilege,
        sessionCurrent: () => active,
        fetchGroups: (_) async => []);
    seed(groupID);
  }

  final api = SangongTestApi();
  late final GroupFeatureStore store;
  final String groupID;
  final int gameType;
  final bool admin, agentOnly, enabled, manageEntry, includeSummary;
  bool canConfigure, canManage;
  bool active = true;
  String? shownGroupID;
  SangongRuntime? runtime;
  FutureOr<dynamic> Function(String groupID)? tenantResponse;
  Map<String, dynamic>? savedConfig;
  Future<void>? capabilityRefresh;

  GroupFeatureContext get context => store.context(
      id: shownGroupID ?? groupID,
      name: '当前群查询测试',
      userID: 'owner',
      admin: admin,
      current: () => active);

  Iterable<SangongCall> get lookups =>
      api.calls.where((call) => call.path.endsWith('/config'));
  Iterable<SangongCall> get businessCalls => api.calls.where((call) =>
      call.useBearerAuth &&
      !call.path.endsWith('/config') &&
      !call.path.endsWith('/snapshot'));

  Map<String, dynamic> currentConfig(String id, {bool enabled = true}) => {
        ...sangongConfig(name: '当前群的厅名', group: id, tenant: id),
        'active': enabled,
      };

  dynamic _respond(SangongCall call) {
    if (call.path.endsWith('/config') &&
        (call.method == 'POST' || call.method == 'PUT')) {
      savedConfig = {
        'ok': true,
        'active': true,
        'tenantId': groupID,
        'imGroupGameId': groupID,
        'name': call.body?['name'] ?? groupID,
        ...?call.body,
      };
      if (call.method == 'PUT') {
        canConfigure = true;
        canManage = true;
      }
      return savedConfig;
    }
    if (call.path.endsWith('/config')) {
      final id = Uri.decodeComponent(call.path.split('/')[5]);
      if (id == groupID && savedConfig != null) return savedConfig;
      return tenantResponse?.call(id) ?? currentConfig(id);
    }
    if (call.path.endsWith('/feature-capabilities')) {
      final encoded = call.path.split('/')[3];
      final id = Uri.decodeComponent(encoded);
      final capabilities = <String, dynamic>{
        'groupID': id,
        'capabilityVersion': 1,
        'sangong': {
          'available': true,
          'canConfigure': canConfigure,
          'canManage': canManage,
          'canOpenAgent': agentOnly,
          'tenantID': agentOnly ? '@agent-game-tenant' : id,
        },
      };
      final pending = capabilityRefresh;
      return pending == null ? capabilities : pending.then((_) => capabilities);
    }
    // Deliberately different: current-group discovery may never fall back here.
    if (call.path.endsWith('/my-config')) {
      return sangongConfig(
          group: '@default-betting-group',
          tenant: '@default-betting-tenant',
          name: '错误的默认厅');
    }
    if (call.path.endsWith('/snapshot')) {
      return {
        ...sangongState(1),
        'groupId': groupID,
        'lastSettledRound': {
          ...sangongState(1)['round'] as Map,
          'id': 17,
          'status': 'settled'
        }
      };
    }
    if (call.path.endsWith('/commands/report.send')) {
      return sangongQueuedReport(call);
    }
    return sangongFixtureResponse(call);
  }

  void seed(String id) => store.seed(GroupInfo(
      groupID: id,
      groupName: '当前群查询测试',
      ex: jsonEncode({
        'gameType': gameType,
        if (includeSummary)
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 1,
            'games': {
              'sangong': {
                'enabled': enabled,
                'manageEntry': manageEntry,
                'agentEntry': agentOnly,
              }
            },
          },
      })));

  Future<void> dispose() async {
    active = false;
    store.dispose();
    await api.closeStreams();
    api.privilege.dispose();
  }
}

Future<void> _pumpChat(WidgetTester tester, _Fixture fixture,
    {bool dark = false}) async {
  addTearDown(fixture.dispose);
  addTearDown(() async {
    await tester.pump(const Duration(seconds: 3));
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    await unmountSangong(tester);
  });
  await fixture.store.loadCapabilities(fixture.groupID);
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: EasyLoading.init(),
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: fixture.store,
                  builder: (_, __) => SangongFeatureHost(
                      featureContext: fixture.context,
                      builder: (context, status, overlay) {
                        fixture.runtime = SangongScope.read(context);
                        return Stack(fit: StackFit.expand, children: [
                          Positioned.fill(
                              child: Column(children: [
                            status,
                            const Expanded(
                                child:
                                    Center(child: Text('群聊正文', key: _chatKey))),
                          ])),
                          overlay,
                        ]);
                      }))))));
  await _flush(tester);
}

Future<void> _flush(WidgetTester tester) async {
  await flushSangong(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await flushSangong(tester);
}

void _openManage(WidgetTester tester, _Fixture fixture) =>
    unawaited(SangongModule.openManage(tester.element(find.byKey(_chatKey)),
        featureContext: fixture.context, runtime: fixture.runtime));

void _expectNoDefaultConfigRead(_Fixture fixture) =>
    expect(fixture.api.count('/my-config'), 0);

void _expectNoSetup(WidgetTester tester, _Fixture fixture) {
  expect(find.byType(GroupGameFloatingEntry), findsNothing);
  expect(find.byType(SangongMyConfigPage), findsNothing);
  expect(fixture.businessCalls, isEmpty);
  _expectNoDefaultConfigRead(fixture);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
  });

  for (final dark in [false, true]) {
    testWidgets(
        'current group lookup uses Chat base, encoded ID and no tenant header, dark=$dark',
        (tester) async {
      final fixture = _Fixture(groupID: '@下注/群?#');
      await _pumpChat(tester, fixture, dark: dark);
      final call = fixture.lookups.single;
      expect(call.method, 'GET');
      expect(call.path, _tenantPath(fixture.groupID));
      expect(call.baseUrlOverride, isNull);
      expect(call.useBearerAuth, isTrue);
      expect(call.headers?.containsKey('X-Tenant-Id') ?? false, isFalse);
      expect(call.body, isNull);
      expect(fixture.runtime!.groupTenant.state!.status.name, 'configured');
      expect(fixture.runtime!.groupTenant.state!.config!.imGroupGameId,
          fixture.groupID);
      expect(fixture.runtime!.groupTenant.state!.tenantId, fixture.groupID);
      expect(fixture.runtime!.groupTenant.state!.config!.name, '当前群的厅名');
      expect(find.byType(GroupGameFloatingEntry), findsOneWidget);
      expect(
          tester
              .widget<GroupGameFloatingEntry>(
                  find.byType(GroupGameFloatingEntry))
              .setupOnly,
          isFalse);
      _expectNoDefaultConfigRead(fixture);
      expect(tester.takeException(), isNull);
    });
  }

  for (final admin in [false, true]) {
    testWidgets('only TENANT_NOT_FOUND displays setup, admin=$admin',
        (tester) async {
      final fixture = _Fixture(
          admin: admin, canConfigure: false, canManage: false)
        ..tenantResponse = (_) => throw const GroupFeatureException('当前群没有三公配置',
            code: 'SERVICE_UNAVAILABLE',
            statusCode: 404,
            serverCode: 'TENANT_NOT_FOUND');
      await _pumpChat(tester, fixture);
      final runtime = fixture.runtime!;
      expect(runtime.groupTenant.state!.status.name, 'notFound');
      expect(runtime.canInitialize, admin);
      expect(runtime.canConfigure, admin);
      expect(runtime.canManage, isFalse);
      final entry = tester
          .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry));
      expect(entry.setupOnly, isTrue);
      entry.onOpenSetup!();
      await _flush(tester);
      final page =
          tester.widget<SangongMyConfigPage>(find.byType(SangongMyConfigPage));
      expect(page.groupScoped, isTrue);
      expect(page.initialGameGroupId, fixture.groupID);
      expect(runtime.canInitialize, admin);
      expect(find.text('保存'), admin ? findsOneWidget : findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).readOnly,
          isTrue);
      expect(fixture.businessCalls, isEmpty);
      _expectNoDefaultConfigRead(fixture);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a disabled tenant remains configured and never displays setup',
      (tester) async {
    final fixture = _Fixture();
    fixture.tenantResponse = (id) => fixture.currentConfig(id, enabled: false);
    await _pumpChat(tester, fixture);
    expect(fixture.runtime!.groupTenant.state!.status.name, 'disabled');
    expect(fixture.runtime!.canInitialize, isFalse);
    expect(fixture.runtime!.canManage, isFalse);
    _expectNoSetup(tester, fixture);
    expect(find.byKey(const ValueKey('sangong-host-retry')), findsOneWidget);
    _openManage(tester, fixture);
    await _flush(tester);
    expect(find.byType(SangongMyConfigPage), findsNothing);
    expect(find.textContaining('停用'), findsWidgets);
    _expectNoDefaultConfigRead(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TENANT_ACCESS_DENIED asks for access instead of initial setup',
      (tester) async {
    final fixture = _Fixture()
      ..tenantResponse = (_) => throw const GroupFeatureException('请联系配置者授权当前群',
          code: 'FORBIDDEN',
          statusCode: 403,
          serverCode: 'TENANT_ACCESS_DENIED');
    await _pumpChat(tester, fixture);
    expect(fixture.runtime!.groupTenant.state!.status.name, 'accessDenied');
    expect(fixture.runtime!.canInitialize, isFalse);
    expect(fixture.runtime!.canManage, isFalse);
    _expectNoSetup(tester, fixture);
    expect(find.textContaining('联系'), findsWidgets);
    expect(find.byKey(const ValueKey('sangong-host-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final error in [
    const GroupFeatureException('登录已失效',
        code: 'AUTH_REQUIRED',
        authRequired: true,
        statusCode: 401,
        serverCode: 'AUTH_REQUIRED'),
    const GroupFeatureException('当前账号没有三公特权',
        code: 'FORBIDDEN', statusCode: 403, serverCode: 'PRIVILEGE_REQUIRED'),
    const GroupFeatureException('服务暂不可用',
        code: 'SERVICE_UNAVAILABLE',
        statusCode: 503,
        serverCode: 'SERVICE_UNAVAILABLE'),
    const GroupFeatureException('未知404错误',
        code: 'SERVICE_UNAVAILABLE', statusCode: 404, serverCode: 'NOT_FOUND'),
  ]) {
    testWidgets(
        '${error.statusCode}/${error.serverCode} stays an error without setup',
        (tester) async {
      final fixture = _Fixture()..tenantResponse = (_) => throw error;
      await _pumpChat(tester, fixture);
      expect(fixture.runtime!.groupTenant.state, isNull);
      expect(fixture.runtime!.groupTenant.error, isNotNull);
      expect(fixture.runtime!.canInitialize, isFalse);
      _expectNoSetup(tester, fixture);
      expect(find.byKey(const ValueKey('sangong-host-retry')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a configured tenant with false capabilities is not missing',
      (tester) async {
    final fixture =
        _Fixture(admin: false, canConfigure: false, canManage: false);
    await _pumpChat(tester, fixture);
    expect(fixture.runtime!.groupTenant.state!.status.name, 'configured');
    expect(fixture.runtime!.canInitialize, isFalse);
    expect(fixture.runtime!.canConfigure, isFalse);
    expect(fixture.runtime!.canManage, isFalse);
    _expectNoSetup(tester, fixture);
    _openManage(tester, fixture);
    await _flush(tester);
    expect(find.byType(SangongMyConfigPage), findsNothing);
    expect(find.text('查看我的配置'), findsNothing);
    _expectNoDefaultConfigRead(fixture);
    expect(tester.takeException(), isNull);
  });

  for (final (label, enabled, manageEntry, includeSummary) in [
    ('disabled public switch', false, true, true),
    ('closed management entry', true, false, true),
    ('gameType without groupFeatures', false, false, false),
  ]) {
    testWidgets('configured tenant with $label still enables operator controls',
        (tester) async {
      final fixture = _Fixture(
          enabled: enabled,
          manageEntry: manageEntry,
          includeSummary: includeSummary);
      await _pumpChat(tester, fixture);
      final runtime = fixture.runtime!;
      expect(runtime.groupTenant.state!.status.name, 'configured');
      expect(runtime.groupTenantReady, isTrue);
      expect(fixture.context.capabilities.sangong.canManage, isTrue);
      expect(runtime.canManage, isTrue);
      expect(runtime.manageUnavailableReason, isNull);
      expect(runtime.canInitialize, isFalse);
      final entry = tester
          .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry));
      expect(entry.setupOnly, isFalse);
      expect(fixture.api.streamStarts, 0);
      expect(fixture.api.count('/snapshot'), greaterThanOrEqualTo(1));
      expect(fixture.businessCalls, isEmpty);
      if (!includeSummary) {
        expect(fixture.context.features.valid, isFalse);
        entry.onSendSettleImage();
        await _flush(tester);
        final report = fixture.businessCalls.single;
        expect(report.path, endsWith('/commands/report.send'));
        expect(report.method, 'POST');
        expect(report.useBearerAuth, isTrue);
        expect(report.body!['requestId'], isA<String>());
        expect(report.body!['input'], {'kind': 'settlement', 'roundId': 17});
        expect(find.byType(SangongManageHomePage), findsNothing);
        expect(find.text('图片报表已加入发送队列'), findsOneWidget);
      }

      final actions = GroupFeatureActions.items(
          tester.element(find.byKey(_chatKey)), fixture.context);
      expect(
          actions.firstWhere((item) => item.text == '三公运营').onTap, isNotNull);
      expect(find.byType(SangongMyConfigPage), findsNothing);
      expect(runtime.groupTenant.state!.status.name, 'configured');
      expect(runtime.groupTenant.state!.config!.name, '当前群的厅名');
      expect(
          tester
              .widget<GroupGameFloatingEntry>(
                  find.byType(GroupGameFloatingEntry))
              .setupOnly,
          isFalse);
      expect(fixture.api.streamStarts, 0);
      _expectNoDefaultConfigRead(fixture);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'forced discovery hides old setup and a disabled response cannot initialize',
      (tester) async {
    final fixture = _Fixture(canConfigure: false, canManage: false)
      ..tenantResponse = (_) => throw const GroupFeatureException('当前群没有三公配置',
          code: 'SERVICE_UNAVAILABLE',
          statusCode: 404,
          serverCode: 'TENANT_NOT_FOUND');
    await _pumpChat(tester, fixture);
    final runtime = fixture.runtime!;
    expect(runtime.groupTenant.state!.status.name, 'notFound');
    expect(runtime.canInitialize, isTrue);
    expect(
        tester
            .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
            .setupOnly,
        isTrue);
    final previousLookups = fixture.lookups.length;
    final reply = Completer<dynamic>();
    fixture.tenantResponse = (_) => reply.future;
    final pending = runtime.groupTenant.refresh(force: true);
    await _flush(tester);
    expect(runtime.groupTenant.loading, isTrue);
    expect(runtime.groupTenant.state!.status.name, 'notFound');
    expect(runtime.canInitialize, isFalse);
    expect(runtime.canConfigure, isFalse);
    expect(runtime.canManage, isFalse);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.text('正在确认当前群的三公配置'), findsOneWidget);
    expect(fixture.lookups.length, previousLookups + 1);

    reply.complete(fixture.currentConfig(fixture.groupID, enabled: false));
    await completeSangongRequest(tester, pending);
    await _flush(tester);
    expect(runtime.groupTenant.loading, isFalse);
    expect(runtime.groupTenant.state!.status.name, 'disabled');
    expect(runtime.canInitialize, isFalse);
    expect(runtime.canConfigure, isFalse);
    expect(runtime.canManage, isFalse);
    expect(find.textContaining('停用'), findsWidgets);
    expect(fixture.api.streamStarts, 0);
    expect(fixture.api.count('/snapshot'), 0);
    _expectNoSetup(tester, fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'forced discovery hides an old configured operator until a specific missing response',
      (tester) async {
    final fixture = _Fixture();
    await _pumpChat(tester, fixture);
    final runtime = fixture.runtime!;
    expect(
        tester
            .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
            .setupOnly,
        isFalse);
    final previousStreams = fixture.api.streamStarts;
    expect(previousStreams, 0);
    final previousLookups = fixture.lookups.length;
    final reply = Completer<dynamic>();
    fixture.tenantResponse = (_) => reply.future;
    final pending = runtime.groupTenant.refresh(force: true);
    await _flush(tester);
    expect(runtime.groupTenant.loading, isTrue);
    expect(runtime.groupTenant.state!.status.name, 'configured');
    expect(runtime.groupTenantReady, isFalse);
    expect(runtime.canManage, isFalse);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.text('正在确认当前群的三公配置'), findsOneWidget);
    expect(fixture.lookups.length, previousLookups + 1);
    expect(fixture.api.streamStarts, previousStreams);
    expect(fixture.api.streamStops, 0);

    reply.completeError(const GroupFeatureException('当前群未配置三公',
        code: 'SERVICE_UNAVAILABLE',
        statusCode: 404,
        serverCode: 'TENANT_NOT_FOUND'));
    await completeSangongRequest(tester, pending);
    await _flush(tester);
    expect(runtime.groupTenant.loading, isFalse);
    expect(runtime.groupTenant.state!.status.name, 'notFound');
    expect(runtime.canManage, isFalse);
    expect(
        tester
            .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
            .setupOnly,
        isTrue);
    expect(fixture.api.streamStarts, previousStreams);
    expect(fixture.businessCalls, isEmpty);
    _expectNoDefaultConfigRead(fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tenant response for another game group is an error, not setup',
      (tester) async {
    final fixture = _Fixture();
    fixture.tenantResponse = (id) => {
          ...fixture.currentConfig(id),
          'imGroupGameId': '@another-betting-group',
        };
    await _pumpChat(tester, fixture);
    expect(fixture.runtime!.groupTenant.state, isNull);
    expect(fixture.runtime!.groupTenant.error, isNotNull);
    _expectNoSetup(tester, fixture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'SDK admin initializes the raw current group with empty optional fields',
      (tester) async {
    final fixture = _Fixture(
        groupID: '@create/下注群', canConfigure: false, canManage: false)
      ..tenantResponse = (_) => throw const GroupFeatureException('当前群没有三公配置',
          code: 'SERVICE_UNAVAILABLE',
          statusCode: 404,
          serverCode: 'TENANT_NOT_FOUND');
    await _pumpChat(tester, fixture);
    tester
        .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
        .onOpenSetup!();
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).readOnly,
        isTrue);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.enterText(find.byType(TextField).last, 'im_bot');
    await tester.tap(find.text('保存'));
    await _flush(tester);
    final create = fixture.api.calls.singleWhere((c) => c.method == 'PUT');
    expect(create.path, _tenantPath(fixture.groupID));
    expect(create.useBearerAuth, isTrue);
    expect(create.baseUrlOverride, isNull);
    expect(create.headers?.containsKey('X-Tenant-Id') ?? false, isFalse);
    expect(create.body?['imGroupGameId'], fixture.groupID);
    expect(create.body?.containsKey('name'), isFalse);
    expect(create.body?['imGroupAdminStatsId'], '');
    expect(create.body?['imBotUserId'], 'im_bot');
    expect(fixture.runtime!.groupTenant.state!.status.name, 'configured');
    expect(find.byType(SangongMembersPage), findsNothing);
    expect(
        tester
            .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
            .setupOnly,
        isFalse);
    _expectNoDefaultConfigRead(fixture);
    await tester.pump(const Duration(seconds: 3));
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'current configuration edits PUT its encoded tenant and omit the game binding',
      (tester) async {
    final fixture = _Fixture(groupID: '@update/下注群?#', canManage: false);
    fixture.tenantResponse = (id) => {
          'active': true,
          'tenantId': id,
          'imGroupGameId': id,
          'name': '原厅名',
          'imGroupAdminStatsId': 'old-stats',
          'imGroupLedgerId': 'old-ledger',
          'imBotUserId': 'im_bot',
        };
    await _pumpChat(tester, fixture);
    _openManage(tester, fixture);
    await _flush(tester);
    await tester.tap(find.text('查看我的配置'));
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).readOnly,
        isTrue);
    await tester.enterText(find.byType(TextField).first, '更新后的厅名');
    await tester.enterText(find.byType(TextField).at(2), 'new-stats');
    await tester.enterText(find.byType(TextField).at(3), 'new-ledger');
    await tester.tap(find.text('保存'));
    await _flush(tester);
    final update = fixture.api.calls.singleWhere((c) => c.method == 'PUT');
    expect(update.path, _tenantPath(fixture.groupID));
    expect(update.useBearerAuth, isTrue);
    expect(update.baseUrlOverride, isNull);
    expect(update.headers?.containsKey('X-Tenant-Id') ?? false, isFalse);
    expect(update.body?.containsKey('imGroupGameId'), isFalse);
    expect(update.body?['name'], '更新后的厅名');
    expect(update.body?['imGroupAdminStatsId'], 'new-stats');
    expect(update.body?['imGroupLedgerId'], 'new-ledger');
    expect(fixture.runtime!.groupTenant.state!.config!.name, '更新后的厅名');
    _expectNoDefaultConfigRead(fixture);
    await tester.pump(const Duration(seconds: 3));
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('current-group save stays locked until capabilities refresh',
      (tester) async {
    final fixture = _Fixture(canManage: false);
    await _pumpChat(tester, fixture);
    _openManage(tester, fixture);
    await _flush(tester);
    await tester.tap(find.text('查看我的配置'));
    await _flush(tester);
    final refreshed = Completer<void>();
    fixture.capabilityRefresh = refreshed.future;
    await tester.enterText(find.byType(TextField).last, 'im_bot');
    await tester.tap(find.text('保存'));
    await _flush(tester);
    expect(fixture.api.calls.where((c) => c.method == 'PUT'), hasLength(1));
    expect(find.text('保存中...'), findsOneWidget);
    await tester.tap(find.text('保存中...'));
    await _flush(tester);
    expect(fixture.api.calls.where((c) => c.method == 'PUT'), hasLength(1));
    refreshed.complete();
    fixture.capabilityRefresh = null;
    await _flush(tester);
    expect(find.text('保存中...'), findsNothing);
    _expectNoDefaultConfigRead(fixture);
    expect(tester.takeException(), isNull);
  });

  for (final (name, type, privileged, agentOnly) in [
    ('ordinary', 0, true, false),
    ('mark six', 2, true, false),
    ('unprivileged', 1, false, false),
    ('legacy agent-only SDK group', 1, true, true),
    ('sangong agent SDK group', 4, true, true),
  ]) {
    testWidgets('$name does not query the current group as a game tenant',
        (tester) async {
      final fixture = _Fixture(
          gameType: type,
          privileged: privileged,
          canConfigure: !agentOnly,
          canManage: !agentOnly,
          agentOnly: agentOnly);
      await _pumpChat(tester, fixture);
      expect(fixture.lookups, isEmpty);
      expect(find.byType(GroupGameFloatingEntry), findsNothing);
      if (agentOnly) {
        expect(fixture.runtime!.requiresGroupTenantCheck, isFalse);
        expect(find.byType(SangongAgentFloatingEntry),
            type == 4 ? findsOneWidget : findsNothing);
      }
      _expectNoDefaultConfigRead(fixture);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retry replaces a verified missing state with the current config',
      (tester) async {
    final fixture = _Fixture()
      ..tenantResponse = (_) => throw const GroupFeatureException('当前群没有三公配置',
          code: 'SERVICE_UNAVAILABLE',
          statusCode: 404,
          serverCode: 'TENANT_NOT_FOUND');
    await _pumpChat(tester, fixture);
    expect(
        tester
            .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
            .setupOnly,
        isTrue);
    fixture.tenantResponse = fixture.currentConfig;
    await completeSangongRequest(
        tester, fixture.runtime!.groupTenant.refresh(force: true));
    await _flush(tester);
    expect(fixture.runtime!.groupTenant.state!.status.name, 'configured');
    expect(
        tester
            .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
            .setupOnly,
        isFalse);
    expect(fixture.lookups.length, 2);
    _expectNoDefaultConfigRead(fixture);
    expect(tester.takeException(), isNull);
  });

  for (final invalidation in ['group', 'session', 'privilege']) {
    testWidgets('pending current-group discovery ignores $invalidation changes',
        (tester) async {
      final reply = Completer<dynamic>();
      final fixture = _Fixture();
      fixture.tenantResponse = (id) =>
          id == fixture.groupID ? reply.future : fixture.currentConfig(id);
      await _pumpChat(tester, fixture);
      final oldRuntime = fixture.runtime!;
      expect(oldRuntime.groupTenant.loading, isTrue);
      expect(find.byType(GroupGameFloatingEntry), findsNothing);
      final coalesced = oldRuntime.groupTenant.refresh().then<dynamic>(
          (value) => value,
          onError: (Object _, StackTrace __) => null);
      expect(fixture.lookups.length, 1);
      if (invalidation == 'group') {
        fixture.shownGroupID = '@new-current-group';
        fixture.seed(fixture.shownGroupID!);
        await flushSangong(tester);
        expect(identical(fixture.runtime, oldRuntime), isFalse);
      } else if (invalidation == 'session') {
        fixture.active = false;
      } else {
        fixture.api.privilege.setAllowed(false);
      }
      reply.complete(fixture.currentConfig(fixture.groupID));
      await _flush(tester);
      await coalesced;
      expect(oldRuntime.groupTenant.state?.status.name, isNot('configured'));
      expect(fixture.businessCalls, isEmpty);
      _expectNoDefaultConfigRead(fixture);
      expect(tester.takeException(), isNull);
    });
  }
}
