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
import 'package:openim/pages/group_features/sangong/widgets/sangong_bet_preview_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sangong_test_support.dart';

const _chatKey = ValueKey('operator-routing-chat');

/// Keeps the real group capability epochs, host runtime and guarded routes.
/// Only account verification and HTTP responses are supplied by the fixture.
class _Fixture {
  _Fixture({
    this.groupID = 'group-sangong',
    this.enabled = true,
    this.canManage = false,
    this.configured = true,
    String? configGroup,
    this.configTenant = 'tenant-authorized',
  }) : configGroup = configGroup ?? groupID {
    api.respond = _respond;
    store = GroupFeatureStore(
      api: api,
      accountPrivilege: api.privilege,
      sessionCurrent: () => active,
      fetchGroups: (_) async => [],
    );
    store.seed(GroupInfo(
      groupID: groupID,
      groupName: '三公导航测试',
      ex: jsonEncode({
        'gameType': 1,
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 1,
          'games': {
            'sangong': {
              'enabled': enabled,
              'manageEntry': true,
              'agentEntry': false,
            },
          },
        },
      }),
    ));
  }

  final api = SangongTestApi();
  late final GroupFeatureStore store;
  final String groupID, configGroup, configTenant;
  final bool enabled, configured;
  bool canManage;
  bool active = true;
  String? shownGroupID;
  int capabilityVersion = 1;
  SangongRuntime? runtime;

  GroupFeatureContext get context => store.context(
        id: shownGroupID ?? groupID,
        name: '三公导航测试',
        userID: 'owner',
        admin: true,
        current: () => active,
      );

  Iterable<SangongCall> get operations => api.calls.where((call) =>
      call.useBearerAuth &&
      !call.path.endsWith('/config') &&
      !call.path.endsWith('/my-config') &&
      !call.path.endsWith('/snapshot'));

  Map<String, dynamic> get round => {
        ...Map<String, dynamic>.from(sangongState(1)['round'] as Map),
        'betWindowCloseAt': '2026-10-06T10:00:00Z',
      };

  dynamic _respond(SangongCall call) {
    if (call.path.endsWith('/config')) {
      if (!configured) {
        throw const GroupFeatureException('当前群未配置三公',
            code: 'SERVICE_UNAVAILABLE',
            statusCode: 404,
            serverCode: 'TENANT_NOT_FOUND');
      }
      final currentGroup = Uri.decodeComponent(call.path.split('/')[5]);
      return {
        ...sangongConfig(
            name: '亚多里测试', group: currentGroup, tenant: currentGroup),
        'active': true,
      };
    }
    if (call.path.endsWith('/feature-capabilities')) {
      return {
        'groupID': groupID,
        'capabilityVersion': capabilityVersion,
        'sangong': {
          'available': true,
          'canConfigure': true,
          'canManage': canManage,
          'canOpenAgent': false,
          'tenantID': canManage ? groupID : '',
        },
      };
    }
    if (call.path.endsWith('/my-config')) {
      return {
        ...sangongConfig(
          name: '亚多里测试',
          group: configGroup,
          tenant: configTenant,
          configured: configured,
        ),
        'active': true,
        'imGroupAdminStatsId': groupID,
        'imGroupLedgerId': groupID,
      };
    }
    if (call.path.endsWith('/bet-preview')) {
      return {
        'version': 1,
        'nextBeforeId': 0,
        'preview': {
          'roundId': 18,
          'pendingMessageCount': 2,
          'report': {
            'grandTotal': 300,
            'betCount': 2,
            'doorTotals': {'2': 300},
            'entries': <dynamic>[],
          },
        },
      };
    }
    if (call.path.endsWith('/commands/report.send')) {
      return sangongQueuedReport(call);
    }
    if (call.path.endsWith('/snapshot')) {
      return {
        ...sangongState(1),
        'groupId': groupID,
        'lastSettledRound': {...round, 'id': 17, 'status': 'settled'},
        'round': round,
        'draw': {'roundId': 18, 'complete': true}
      };
    }
    if (call.path.endsWith('/commands/round.settle')) {
      return sangongReceipt(call, {
        'round': {...round, 'status': 'settled'}
      });
    }
    return sangongFixtureResponse(call);
  }

  Future<void> dispose() async {
    active = false;
    store.dispose();
    await api.closeStreams();
    api.privilege.dispose();
  }
}

Future<void> _pumpChat(WidgetTester tester, _Fixture fixture) async {
  addTearDown(fixture.dispose);
  addTearDown(() async {
    // A toast finishes its entrance before installing its dismissal timer.
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
      home: Scaffold(
        body: ListenableBuilder(
          listenable: fixture.store,
          builder: (_, __) => SangongFeatureHost(
            featureContext: fixture.context,
            builder: (context, status, overlay) {
              fixture.runtime = SangongScope.read(context);
              return Stack(fit: StackFit.expand, children: [
                const Positioned.fill(
                  child: Center(child: Text('群聊正文', key: _chatKey)),
                ),
                overlay,
              ]);
            },
          ),
        ),
      ),
    ),
  ));
  await _flush(tester);
}

Future<void> _flush(WidgetTester tester) async {
  await flushSangong(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await flushSangong(tester);
}

GroupGameFloatingEntry _operator(WidgetTester tester) =>
    tester.widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry));

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

void _openManage(WidgetTester tester, _Fixture fixture) => unawaited(
      SangongModule.openManage(tester.element(find.byKey(_chatKey)),
          featureContext: fixture.context, runtime: fixture.runtime),
    );

void _expectNoConfigOrManagementPage() {
  expect(find.byType(SangongMyConfigPage), findsNothing);
  expect(find.byType(SangongManageHomePage), findsNothing);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
  });

  for (final (enabled, canManage) in [(true, false), (false, false)]) {
    testWidgets(
        'configured owner sees a reason and explicit config link when enabled=$enabled canManage=$canManage',
        (tester) async {
      final fixture = _Fixture(enabled: enabled, canManage: canManage);
      await _pumpChat(tester, fixture);
      expect(fixture.runtime!.canConfigure, isTrue);
      expect(fixture.runtime!.groupTenant.state!.config!.configured, isTrue);
      expect(fixture.runtime!.canManage, isFalse);
      expect(find.byType(GroupGameFloatingEntry), findsNothing);

      _openManage(tester, fixture);
      await _flush(tester);
      expect(find.text('三公管理'), findsOneWidget);
      expect(
          find.text(fixture.runtime!.manageUnavailableReason!), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('查看我的配置'), findsOneWidget);
      _expectNoConfigOrManagementPage();
      expect(fixture.operations, isEmpty);

      await tester.tap(find.text('查看我的配置'));
      await _flush(tester);
      expect(find.byType(SangongMyConfigPage), findsOneWidget);
      expect(find.text('亚多里测试'), findsOneWidget);
      expect(fixture.operations, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('only an explicitly unconfigured owner is routed to first setup',
      (tester) async {
    final fixture = _Fixture(configured: false);
    await _pumpChat(tester, fixture);
    expect(fixture.runtime!.groupTenant.state!.status.name, 'notFound');
    expect(fixture.api.count('/my-config'), 0);
    expect(_operator(tester).setupOnly, isTrue);
    _operator(tester).onOpenSetup!();
    await _flush(tester);
    expect(find.byType(SangongMyConfigPage), findsOneWidget);
    expect(find.byType(SangongManageHomePage), findsNothing);
    expect(fixture.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'retained operator callbacks reject revoked management capabilities',
      (tester) async {
    final fixture = _Fixture(canManage: true);
    await _pumpChat(tester, fixture);
    final entry = _operator(tester);
    fixture.canManage = false;
    fixture.capabilityVersion++;
    await completeSangongRequest(
        tester, fixture.store.loadCapabilities(fixture.groupID, force: true));
    await _flush(tester);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    for (final action in [
      entry.onOpenCutoff,
      entry.onOpenSettle,
      entry.onSendSettleImage,
      entry.onSendSettleBill,
      entry.onSendPointsImage,
      entry.onSendTrendImage,
      entry.onOpenRulesSettings,
    ]) {
      action();
      await _flush(tester);
      _expectNoConfigOrManagementPage();
      expect(find.byType(SangongGameRulesSettingsPage), findsNothing);
      expect(_navigator(tester).canPop(), isFalse);
      expect(fixture.operations, isEmpty);
    }
    expect(fixture.runtime!.canManage, isFalse);
    expect(find.text(fixture.runtime!.manageUnavailableReason!), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stats group reads its current binding instead of default config',
      (tester) async {
    const statsGroup = '@sgtestb5969a8168814c95';
    const bettingGroup = '@z8hFfDvVQP0x';
    final fixture = _Fixture(
      groupID: statsGroup,
      enabled: false,
      canManage: true,
      configGroup: bettingGroup,
      configTenant: bettingGroup,
    )..capabilityVersion = 0;
    await _pumpChat(tester, fixture);
    expect(fixture.context.capabilities.sangong.canManage, isTrue);
    expect(fixture.context.capabilities.sangong.tenantID, statsGroup);
    expect(fixture.runtime!.http.tenantId, statsGroup);
    expect(
        fixture.runtime!.groupTenant.state!.config!.imGroupGameId, statsGroup);
    expect(fixture.runtime!.groupTenant.state!.config!.name, '亚多里测试');
    expect(fixture.runtime!.canManage, isTrue);
    expect(_operator(tester).setupOnly, isFalse);

    _openManage(tester, fixture);
    await _flush(tester);
    expect(find.byType(SangongManageHomePage), findsOneWidget);
    expect(find.byType(SangongMyConfigPage), findsNothing);
    expect(find.text('查看我的配置'), findsNothing);
    expect(fixture.operations, isEmpty);
    for (final call
        in fixture.api.calls.where((c) => c.path.endsWith('/config'))) {
      expect(call.headers?.containsKey('X-Tenant-Id') ?? false, isFalse);
    }
    expect(fixture.api.count('/my-config'), 0);
    expect(fixture.runtime!.http.tenantId, statsGroup);
    expect(tester.takeException(), isNull);
  });

  for (final recovered in [false, true]) {
    testWidgets(
        'cutoff continues its preview operation after recovery=$recovered',
        (tester) async {
      final fixture = _Fixture(canManage: true);
      await _pumpChat(tester, fixture);
      final entry = _operator(tester);
      final previousCapabilityReads =
          fixture.api.count('/feature-capabilities');
      if (recovered) {
        fixture.store.invalidateCapabilities(fixture.groupID);
        fixture.capabilityVersion++;
        expect(fixture.runtime!.canManage, isFalse);
      }
      entry.onOpenCutoff();
      await _flush(tester);
      expect(fixture.runtime!.canManage, isTrue);
      expect(fixture.api.count('/snapshot'), recovered ? 3 : 2);
      expect(fixture.api.count('/bet-preview'), 1);
      expect(find.byType(SangongBetPreviewSheet), findsOneWidget);
      _expectNoConfigOrManagementPage();
      if (recovered) {
        expect(fixture.api.count('/feature-capabilities'),
            greaterThan(previousCapabilityReads));
      }
      _navigator(tester).pop();
      await _flush(tester);
      expect(fixture.api.count('/commands/round.close'), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('authorized report buttons queue the matching four report kinds',
      (tester) async {
    final fixture = _Fixture(canManage: true);
    await _pumpChat(tester, fixture);
    final entry = _operator(tester);
    for (final (action, kind) in [
      (entry.onSendSettleImage, 'settlement'),
      (entry.onSendSettleBill, 'bill'),
      (entry.onSendPointsImage, 'points'),
      (entry.onSendTrendImage, 'trend'),
    ]) {
      action();
      await _flush(tester);
      final call = fixture.operations.singleWhere((c) =>
          c.path.endsWith('/commands/report.send') &&
          (c.body?['input'] as Map?)?['kind'] == kind);
      expect(call.method, 'POST');
      if (kind == 'settlement' || kind == 'bill') {
        expect((call.body!['input'] as Map)['roundId'], 17);
      }
      _expectNoConfigOrManagementPage();
      expect(_navigator(tester).canPop(), isFalse);
    }
    expect(fixture.operations.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authorized settle uses the current draws and round settle APIs',
      (tester) async {
    final fixture = _Fixture(canManage: true);
    await _pumpChat(tester, fixture);
    _operator(tester).onOpenSettle();
    await _flush(tester);
    expect(fixture.api.count('/snapshot'), 3);
    final settle = fixture.operations
        .singleWhere((c) => c.path.endsWith('/commands/round.settle'));
    expect(settle.method, 'POST');
    expect(fixture.operations.where((c) => c.path.endsWith('/admin/draws')),
        isEmpty);
    _expectNoConfigOrManagementPage();
    expect(_navigator(tester).canPop(), isFalse);
    expect(tester.takeException(), isNull);
    // Widget-test timer invariants run before package-level tearDown callbacks.
    // Finish the real success toast while its EasyLoading overlay is mounted.
    await tester.pump(const Duration(seconds: 3));
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
  });

  for (final enabled in [true, false]) {
    testWidgets(
        'settings uses current tenant capabilities with public enabled=$enabled',
        (tester) async {
      final fixture = _Fixture(enabled: enabled, canManage: true);
      await _pumpChat(tester, fixture);
      _operator(tester).onOpenRulesSettings();
      await _flush(tester);
      expect(find.byType(SangongGameRulesSettingsPage), findsOneWidget);
      _expectNoConfigOrManagementPage();
      expect(fixture.api.count('/settings'), 0);
      expect(fixture.api.count('/snapshot'), 2);
      expect(fixture.api.count('/my-config'), 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['settle', 'settings']) {
    for (final invalidation in ['group', 'session']) {
      testWidgets(
          '$action ignores a recovered old preflight after $invalidation changes',
          (tester) async {
        final fixture = _Fixture(canManage: true);
        await _pumpChat(tester, fixture);
        final oldRuntime = fixture.runtime!;
        final entry = _operator(tester);
        final beforeReads = fixture.api.count('/feature-capabilities');
        final reply = Completer<dynamic>();
        fixture.api.respond = (call) =>
            call.path.endsWith('/feature-capabilities')
                ? reply.future
                : fixture._respond(call);
        fixture.store.invalidateCapabilities(fixture.groupID);
        if (action == 'settle') {
          entry.onOpenSettle();
        } else {
          entry.onOpenRulesSettings();
        }
        await flushSangong(tester);
        expect(fixture.api.count('/feature-capabilities'), beforeReads + 1);
        expect(fixture.operations, isEmpty);

        if (invalidation == 'group') {
          fixture.shownGroupID = 'different-group';
          fixture.store.seed(GroupInfo(
              groupID: fixture.shownGroupID!,
              groupName: '另一个群',
              ex: '{"gameType":1}'));
          await flushSangong(tester);
          expect(identical(fixture.runtime, oldRuntime), isFalse);
        } else {
          fixture.active = false;
        }
        fixture.canManage = true;
        fixture.capabilityVersion++;
        reply.complete(fixture._respond(
            SangongCall('/feature-capabilities', 'GET', null, null, null)));
        await _flush(tester);

        expect(oldRuntime.isSessionCurrent, isFalse);
        expect(fixture.operations, isEmpty);
        expect(fixture.api.count('/commands/round.settle'), 0);
        expect(fixture.api.count('/settings'), 0);
        expect(find.byType(SangongGameRulesSettingsPage), findsNothing);
        _expectNoConfigOrManagementPage();
        expect(_navigator(tester).canPop(), isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
