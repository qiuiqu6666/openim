import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/diagnostics/group_feature_api_diagnostics.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';
import 'package:openim/pages/group_features/sangong/models/binding/sangong_group_tenant_state.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../../../support/account_privilege_fixture.dart';
export '../../../support/account_privilege_fixture.dart';

String? expectedSangongRequestTenant(
    {String verifiedTenant = 'tenant-authorized', bool skipTenant = false}) {
  return null; // v2 resolves tenants exclusively from the current group URL.
}

class SangongCall {
  SangongCall(this.path, this.method, this.body, this.query, this.headers,
      {this.baseUrlOverride, this.useBearerAuth = false});
  final String path, method;
  final String? baseUrlOverride;
  final bool useBearerAuth;
  final Map<String, dynamic>? body, query, headers;
}

/// Exercises the real per-group Dio adapter while replacing only the transport.
class SangongTestApi extends GroupFeatureApi {
  SangongTestApi()
      : super(
            baseUrl: 'https://fixture.example',
            tokenProvider: () => 'fixture-chat-token',
            userProvider: () => 'owner');
  final calls = <SangongCall>[];
  final privilege = FixtureAccountPrivilege();
  FutureOr<dynamic> Function(SangongCall call)? respond;
  int streamStarts = 0, streamStops = 0;
  final streamCalls = <SangongCall>[];
  final streams = <StreamController<String>>[];
  @override
  Future<dynamic> requestData(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken,
      bool preserveEnvelope = false,
      String? baseUrlOverride,
      bool useBearerAuth = false,
      GroupFeatureApiDiagnostics? diagnostics}) async {
    final call = SangongCall(path, method, body, query, headers,
        baseUrlOverride: baseUrlOverride, useBearerAuth: useBearerAuth);
    calls.add(call);
    if (respond != null) return await respond!(call);
    return sangongFixtureResponse(call);
  }

  @override
  Stream<String> eventStream(String path,
      {Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken,
      String? baseUrlOverride,
      bool useBearerAuth = false,
      GroupFeatureApiDiagnostics? diagnostics}) {
    streamStarts++;
    streamCalls.add(SangongCall(path, 'GET', null, query, headers,
        baseUrlOverride: baseUrlOverride, useBearerAuth: useBearerAuth));
    late StreamController<String> controller;
    controller = StreamController<String>(onCancel: () {
      streamStops++;
    });
    streams.add(controller);
    return controller.stream;
  }

  int count(String suffix) =>
      calls.where((call) => call.path.endsWith(suffix)).length;
  Future<void> closeStreams() async {
    for (final stream in streams) {
      await stream.close();
    }
  }
}

/// Business-page fixtures start after a successful current-group tenant lookup.
/// Binding discovery tests construct SangongRuntime directly to start unknown.
SangongRuntime sangongTestRuntime(GroupFeatureContext context) {
  final runtime = SangongRuntime(context);
  if (runtime.requiresGroupTenantCheck) {
    runtime.groupTenant.applySaved(SangongGroupTenantState(
      status: SangongGroupTenantStatus.configured,
      tenantId: context.capabilities.sangong.tenantID,
      config: SangongMyConfig.fromJson({
        ...sangongConfig(
            group: context.groupID,
            tenant: context.capabilities.sangong.tenantID),
        'active': true,
      }),
    ));
  }
  return runtime;
}

GroupFeatureContext sangongTestContext(
  SangongTestApi api, {
  String groupID = 'group-sangong',
  String userID = 'owner',
  GroupGameType gameType = GroupGameType.sangong,
  bool enabled = true,
  bool manageEntry = true,
  bool agentEntry = true,
  bool canConfigure = true,
  bool canManage = true,
  bool canOpenAgent = true,
  bool canViewHistory = true,
  String tenantID = 'tenant-authorized',
  bool requiresTenantSelection = false,
  int capabilityVersion = 1,
  bool Function()? current,
  bool Function()? capabilitiesCurrent,
  Stream<Map<String, dynamic>>? events,
  void Function(Map<String, dynamic>)? onFeaturesChanged,
}) =>
    GroupFeatureContext(
        groupID: groupID,
        groupName: '三公交流群',
        currentUserID: userID,
        gameType: gameType,
        api: api,
        accountPrivilege: api.privilege,
        isGroupAdmin: canConfigure,
        features: GroupFeatures(
            valid: true,
            revision: 1,
            sangong: GroupGameFeature(
                enabled: enabled,
                manageEntry: manageEntry,
                agentEntry: agentEntry,
                rebateHistoryEntry: canViewHistory)),
        capabilities: GroupFeatureCapabilities(
            version: capabilityVersion,
            sangong: GroupGameCapabilities(
                canConfigure: canConfigure,
                canManage: canManage,
                canOpenAgent: canOpenAgent,
                canViewRebateHistory: canViewHistory,
                tenantID: tenantID,
                raw: {'requiresTenantSelection': requiresTenantSelection})),
        sessionCurrent: current ?? () => true,
        capabilitiesCurrent: capabilitiesCurrent ?? () => true,
        onFeaturesChanged: onFeaturesChanged ?? (_) {},
        events: events ?? const Stream<Map<String, dynamic>>.empty());

Map<String, dynamic> sangongConfig(
        {String name = '一号厅',
        String group = 'group-sangong',
        String tenant = 'tenant-authorized',
        bool configured = true}) =>
    {
      'configured': configured,
      'tenantId': tenant,
      'name': name,
      'imGroupGameId': group,
      'imGroupAdminStatsId': 'group-statistics',
      'imGroupLedgerId': 'group-credit',
      'imBotUserId': 'bot-sangong',
      'myRole': 'owner',
      'canEditConfig': true,
      'canManageMembers': true,
    };

Map<String, dynamic> sangongState(int version) => {
      'schemaVersion': 2,
      'groupId': 'group-sangong',
      'botUserId': 'bot-sangong',
      'version': version,
      'status': 'betting',
      'settings': SangongGameSettings.defaults().toJson(),
      'round': {
        'id': 18,
        'sessionId': 2,
        'periodNo': 3,
        'status': 'betting',
        'bankerNickname': '冬',
        'bankerDoor': 1,
        'bankerLimit': 2000,
        'betWindowOpenAt': '2026-10-04T10:00:00Z'
      },
      'pending': {
        'open': true,
        'messageCount': 2,
        'doorTotals': {'2': 200, '3': 100},
        'grandTotal': 300
      },
      'placed': {
        'betCount': 2,
        'doorTotals': {'2': 200, '3': 100},
        'grandTotal': 300
      },
    };

Map<String, dynamic> sangongMessageEvent(int version,
        {String sender = 'bot-sangong',
        String group = 'group-sangong',
        Map<String, dynamic>? state}) =>
    {
      'key': 'sangongStateMessage',
      'groupID': group,
      'senderID': sender,
      'serverMsgID': 'message-$version',
      'seq': version + 1,
      'data': {
        'type': 'sangong.event',
        'schemaVersion': 2,
        'groupId': group,
        'eventId': 'event-$version',
        'version': version,
        'state': state ?? {...sangongState(version), 'groupId': group},
      },
    };

dynamic sangongFixtureResponse(SangongCall call) {
  if (call.path.contains('/agent-groups/') && call.path.endsWith('/tenants')) {
    return {
      'agentImUserId': 'owner',
      'agentImGroupId': Uri.decodeComponent(call.path.split('/')[5]),
      'tenants': [
        {
          'tenantId': 'tenant-authorized',
          'name': '一号厅',
          'imGroupGameId': 'game-room'
        }
      ],
    };
  }
  if (call.path.startsWith('/sangong/api/v2/groups/') &&
      call.path.endsWith('/config')) {
    final group = Uri.decodeComponent(call.path.split('/')[5]);
    return {
      'ok': true,
      'data': {...sangongConfig(group: group), 'active': true}
    };
  }
  if (call.path.endsWith('/snapshot')) {
    final group = Uri.decodeComponent(call.path.split('/')[5]);
    return {
      'ok': true,
      'data': {...sangongState(1), 'groupId': group}
    };
  }
  if (call.path.endsWith('/access')) {
    return {
      'ok': true,
      'data': {'members': []}
    };
  }
  if (call.path.contains('/access/') && call.method == 'DELETE') {
    return {'ok': true, 'data': {}};
  }
  if (call.path.endsWith('/users')) {
    return {
      'ok': true,
      'data': {'users': [], 'version': 1, 'total': 0, 'nextBeforeId': 0}
    };
  }
  if (call.path.endsWith('/sessions')) return {'sessions': []};
  if (call.path.endsWith('/user-report')) {
    return sangongUserReport(
        imUserId: call.query?['imUserId'] as String? ?? 'owner');
  }
  if (call.path.endsWith('/session')) {
    return {'status': 'running', 'round': sangongState(1)['round']};
  }
  if (call.path.endsWith('/settings')) {
    return {'settings': SangongGameSettings.defaults().toJson()};
  }
  if (call.path.endsWith('/context')) {
    return {
      'showAgentEntry': true,
      'tenantId': 'tenant-authorized',
      'agentImGroupId': Uri.decodeComponent(call.path.split('/')[5]),
      'agentImUserId': 'owner',
      'agent': {'userId': 8, 'imUserId': 'owner', 'balance': 1000}
    };
  }
  if (call.path.endsWith('/team-summary')) {
    return {
      'batch': {
        'status': 'running',
        'batchNo': '20261004-1',
        'startedAt': '2026-10-04 10:00'
      },
      'summary': {
        'memberCount': 2,
        'playerTurnover': 1200,
        'bankerTurnover': 800,
        'totalTurnover': 2000,
        'rebateAmount': 60,
        'pendingRebate': 30
      },
      'version': 1,
      'nextBeforeId': 0,
      'members': [
        {
          'imUserId': 'winter',
          'nickname': '冬',
          'levelNo': 1,
          'playerTurnover': 1200,
          'bankerTurnover': 800,
          'rebateAmount': 60
        }
      ],
    };
  }
  if (call.path.endsWith('/team')) {
    return {'version': 1, 'nextBeforeId': 0, 'members': []};
  }
  throw GroupFeatureException('Fixture has no endpoint: ${call.path}',
      code: 'FIXTURE_MISSING');
}

Map<String, dynamic> sangongReceipt(
        SangongCall call, Map<String, dynamic> data) =>
    {
      'ok': true,
      'requestId': call.body?['requestId'],
      'data': data,
    };

Map<String, dynamic> sangongQueuedReport(SangongCall call) =>
    sangongReceipt(call, {
      'queued': true,
      'type': call.body?['input']['kind'],
      'reportId': 'report-1',
      'deliveryIds': ['delivery-1'],
      if (call.body?['input']['roundId'] != null)
        'roundId': call.body?['input']['roundId'],
    });

Map<String, dynamic> sangongUserReport(
        {String imUserId = 'owner',
        List<Map<String, dynamic>> entries = const [],
        int? total,
        int nextBeforeId = 0,
        Map<String, dynamic> summary = const {},
        Map<String, dynamic> user = const {}}) =>
    {
      'version': 1,
      'user': {'userId': 19, 'imUserId': imUserId, 'balance': 1000, ...user},
      'summary': summary,
      'entries': entries,
      'totalEntries': total ?? entries.length,
      'nextBeforeId': nextBeforeId,
    };

Future<void> pumpSangongPage(
    WidgetTester tester, SangongRuntime runtime, Widget page,
    {bool dark = false,
    TargetPlatform platform = TargetPlatform.android,
    GlobalKey? boundary,
    String? fontFamily}) async {
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              platform: platform,
              fontFamily: fontFamily,
              scaffoldBackgroundColor:
                  dark ? const Color(0xff141414) : const Color(0xfff5f6f8),
              colorSchemeSeed: const Color(0xff0089ff)),
          home: RepaintBoundary(
              key: boundary,
              child: SangongScope(runtime: runtime, child: page)))));
  await flushSangong(tester);
}

Future<void> flushSangong(WidgetTester tester) async {
  // Dio's interceptor Futures and preferences need microtasks, but infinite
  // loading animations / open SSE must not make this wait for idle forever.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<T> completeSangongRequest<T>(WidgetTester tester, Future<T> task) async {
  T? value;
  Object? failure;
  StackTrace? trace;
  // Attach the failure handler before pumping the fake timer used by Dio.
  final completion = task.then<void>((result) {
    value = result;
  }, onError: (Object error, StackTrace stack) {
    failure = error;
    trace = stack;
  });
  await flushSangong(tester);
  await completion;
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return value as T;
}

Future<void> rejectSangongRequest(
    WidgetTester tester, Future<dynamic> task, Matcher matcher) async {
  final expectation = expectLater(task, throwsA(matcher));
  await flushSangong(tester);
  await expectation;
}

Future<void> unmountSangong(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
