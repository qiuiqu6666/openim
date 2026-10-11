import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_agent_floating_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sangong_test_support.dart';

/// Real store epochs, feature host, runtime, routes and API adapters; only the
/// remote transport and account verification are controlled by the tests.
class RouteRevalidationFixture {
  RouteRevalidationFixture({this.agent = false}) {
    if (agent) {
      api.privilege.setAllowed(false);
      canManage = false;
      canConfigure = false;
      canOpenAgent = true;
      tenantID = 'agent-hall';
    }
    api.respond = respond;
    store = GroupFeatureStore(
      api: api,
      accountPrivilege: api.privilege,
      sessionCurrent: () => active,
      fetchGroups: (_) async => [],
    );
    store.seed(GroupInfo(
      groupID: groupID,
      groupName: '三公导航测试',
      ex: jsonEncode({'gameType': agent ? 4 : 1}),
    ));
  }

  static const groupID = 'group-sangong';
  static const chatKey = ValueKey('revalidation-chat');
  final bool agent;
  final api = SangongTestApi();
  late final GroupFeatureStore store;
  late SangongRuntime runtime;
  bool active = true, canManage = true;
  bool canOpenAgent = false;
  bool canConfigure = true;
  String tenantID = groupID;
  int version = 1, roundID = 18;
  Completer<dynamic>? capabilityRead, configRead;

  Map<String, dynamic> get capabilities => {
        'groupID': groupID,
        'capabilityVersion': version,
        'sangong': {
          'available': true,
          'canConfigure': canConfigure,
          'canManage': canManage,
          'canOpenAgent': canOpenAgent,
          'canViewRebateHistory': canOpenAgent,
          'tenantID': tenantID,
        },
      };

  Map<String, dynamic> get config => {
        ...sangongConfig(group: groupID, tenant: tenantID),
        'active': true,
      };

  dynamic respond(SangongCall call) {
    if (call.path.endsWith('/tenants')) {
      return {
        'agentImUserId': 'owner',
        'agentImGroupId': groupID,
        'tenants': [
          {'tenantId': tenantID, 'name': '代理测试厅', 'imGroupGameId': 'game-room'}
        ]
      };
    }
    if (call.path.endsWith('/member')) {
      return {
        'member': {'imUserId': 'owner', 'nickname': '代理', 'balance': 100}
      };
    }
    if (call.path.endsWith('/member-daily')) return {'days': []};
    if (call.path.endsWith('/feature-capabilities')) {
      return capabilityRead?.future ?? capabilities;
    }
    if (call.path.endsWith('/config')) return configRead?.future ?? config;
    if (call.path.endsWith('/snapshot')) {
      return {
        ...sangongState(version),
        'round': {
          ...Map<String, dynamic>.from(sangongState(version)['round'] as Map),
          'id': roundID,
          'betWindowCloseAt': '2026-10-06T10:00:00Z',
        },
        'draw': {'roundId': roundID, 'complete': false},
      };
    }
    if (call.path.endsWith('/bet-preview')) {
      return {
        'version': version,
        'nextBeforeId': 0,
        'preview': {
          'roundId': roundID,
          'pendingMessageCount': version,
          'report': {'grandTotal': 300, 'betCount': 2, 'entries': []},
        },
      };
    }
    return sangongFixtureResponse(call);
  }

  NavigatorState navigator(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator));

  Future<void> pumpChat(WidgetTester tester, {bool dark = false}) async {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
    addTearDown(() async {
      await tester.pump(const Duration(seconds: 3));
      await EasyLoading.dismiss(animation: false);
      await unmountSangong(tester);
      active = false;
      store.dispose();
      await api.closeStreams();
      api.privilege.dispose();
    });
    await store.loadCapabilities(groupID);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: EasyLoading.init(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: store,
            builder: (_, __) => SangongFeatureHost(
              featureContext: store.context(
                id: groupID,
                name: '三公导航测试',
                userID: 'owner',
                admin: true,
                current: () => active,
              ),
              builder: (context, banner, overlay) {
                runtime = SangongScope.read(context);
                return Stack(fit: StackFit.expand, children: [
                  const Center(child: Text('群聊正文', key: chatKey)),
                  overlay,
                ]);
              },
            ),
          ),
        ),
      ),
    ));
    await flush(tester);
  }

  Future<void> open(WidgetTester tester, String entry) async {
    if (agent) {
      final buttons = tester.widget<SangongAgentFloatingEntry>(
          find.byType(SangongAgentFloatingEntry));
      switch (entry) {
        case 'team':
          buttons.onOpenQuery();
        case 'dashboard':
          buttons.onOpenTeam();
        case 'personal':
          buttons.onOpenPersonal();
      }
      await flush(tester);
      return;
    }
    final buttons = tester
        .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry));
    switch (entry) {
      case 'rules':
        buttons.onOpenRulesSettings();
      case 'cutoff':
        buttons.onOpenCutoff();
      case 'settle':
        buttons.onOpenSettle();
      case 'manage':
        unawaited(SangongModule.openManage(
          tester.element(find.byKey(chatKey)),
          featureContext: runtime.featureContext,
          runtime: runtime,
        ));
    }
    await flush(tester);
  }

  void invalidate() {
    version++;
    capabilityRead = Completer<dynamic>();
    store.invalidateCapabilities(groupID);
  }

  void resolveCapabilities() {
    final pending = capabilityRead!;
    capabilityRead = null;
    pending.complete(capabilities);
  }

  void resolveConfig() {
    final pending = configRead!;
    configRead = null;
    pending.complete(config);
  }

  void expectNoCommands() => expect(
      api.calls.where((call) => call.path.contains('/commands/')), isEmpty);

  static Future<void> flush(WidgetTester tester) async {
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await flushSangong(tester);
  }
}
