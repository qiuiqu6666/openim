import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/api/diagnostics/sangong_api_debug_log.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/models/binding/sangong_group_tenant_state.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';

import '../../sangong_test_support.dart';

const _ownerConfig = SangongMyConfig(
  configured: true,
  tenantId: 'tenant-authorized',
  imGroupGameId: 'group-sangong',
  myRole: 'owner',
  canEditConfig: true,
  canManageMembers: true,
);

Map<String, dynamic> _permissionPayload(List<String> logs) => jsonDecode(logs
    .where((line) => line.startsWith('[三公API][-][权限检查]'))
    .map((line) => line.replaceFirst(
        RegExp(r'^\[三公API\]\[[^\]]*\]\[[^\]]*\]\[\d+/\d+\] '), ''))
    .join()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SangongTestApi api;
  setUp(() {
    api = SangongTestApi();
    addTearDown(api.privilege.dispose);
  });

  SangongRuntime runtimeFor(GroupFeatureContext context,
      {String? configuredTenantId, bool confirmed = true}) {
    final runtime = confirmed && configuredTenantId == null
        ? sangongTestRuntime(context)
        : SangongRuntime(context, configuredTenantId: configuredTenantId);
    if (confirmed && configuredTenantId != null) {
      runtime.groupTenant.applySaved(SangongGroupTenantState(
          status: SangongGroupTenantStatus.configured,
          tenantId: context.groupID,
          config: _ownerConfig.copyWith(
              tenantId: context.groupID, imGroupGameId: context.groupID)));
    }
    addTearDown(runtime.dispose);
    return runtime;
  }

  void expectReadOnlyReason(SangongRuntime runtime, String? reason) {
    final context = runtime.featureContext;
    final feature = context.features;
    final capability = context.capabilities;
    final config = runtime.config.config;
    final hadConfig = runtime.config.hasCachedConfig;
    final tenant = runtime.http.tenantId;
    final canManage = runtime.canManage;
    final registration = runtime.groupTenant.state;
    final registrationError = runtime.groupTenant.error;
    final registrationLoading = runtime.groupTenant.loading;
    for (var read = 0; read < 3; read++) {
      expect(runtime.manageUnavailableReason, reason);
    }
    expect(runtime.featureContext, same(context));
    expect(runtime.featureContext.features, same(feature));
    expect(runtime.featureContext.capabilities, same(capability));
    expect(runtime.config.config, same(config));
    expect(runtime.config.hasCachedConfig, hadConfig);
    expect(runtime.http.tenantId, tenant);
    expect(runtime.canManage, canManage);
    expect(runtime.groupTenant.state, same(registration));
    expect(runtime.groupTenant.error, same(registrationError));
    expect(runtime.groupTenant.loading, registrationLoading);
    expect(api.calls, isEmpty);
    expect(api.streamStarts, 0);
  }

  test('ready management has no diagnostic reason and dispatches no request',
      () async {
    final runtime = runtimeFor(sangongTestContext(api));
    expect(runtime.canManage, isTrue);
    expectReadOnlyReason(runtime, null);
    await runtime.config.applySaved(_ownerConfig);
    expectReadOnlyReason(runtime, null);
  });

  test('configured owner cannot replace missing private management permission',
      () async {
    final runtime = runtimeFor(sangongTestContext(api,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false,
        tenantID: ''));
    await runtime.config.applySaved(_ownerConfig);
    expect(runtime.config.config.isOwner, isTrue);
    expect(runtime.config.config.configured, isTrue);
    expect(runtime.canManage, isFalse);
    expect(runtime.canManageMembers, isFalse);
    expect(runtime.http.tenantId, isNull);
    expectReadOnlyReason(runtime, '当前账号没有该群的三公运营权限');
    expect(runtime.http.tenantId, isNull);
  });

  test('configuration authority and a confirmed tenant still do not grant ops',
      () async {
    final runtime = runtimeFor(sangongTestContext(api,
        canConfigure: true,
        canManage: false,
        canOpenAgent: false,
        tenantID: ''));
    await runtime.config.applySaved(_ownerConfig);
    expect(runtime.canConfigure, isTrue);
    expect(runtime.http.tenantId, 'tenant-authorized');
    expect(runtime.canManage, isFalse);
    expectReadOnlyReason(runtime, '当前账号没有该群的三公运营权限');
  });

  for (final flag in ['enabled', 'manageEntry']) {
    test('registered game uses aggregate management despite closed $flag', () {
      final runtime = runtimeFor(sangongTestContext(api,
          enabled: flag != 'enabled', manageEntry: flag != 'manageEntry'));
      expect(runtime.requiresGroupTenantCheck, isTrue);
      expect(runtime.groupTenantReady, isTrue);
      expect(runtime.featureContext.capabilities.sangong.canManage, isTrue);
      expect(runtime.http.hasTenant, isTrue);
      expect(runtime.canManage, isTrue);
      expectReadOnlyReason(runtime, null);
    });

    test('registered game cannot operate without aggregate permission ($flag)',
        () {
      final runtime = runtimeFor(sangongTestContext(api,
          enabled: flag != 'enabled',
          manageEntry: flag != 'manageEntry',
          canManage: false));
      expect(runtime.groupTenantReady, isTrue);
      expect(runtime.canManage, isFalse);
      expectReadOnlyReason(runtime, '当前账号没有该群的三公运营权限');
    });

    test('legacy management retains the $flag public gate', () {
      final runtime = runtimeFor(sangongTestContext(api,
          gameType: GroupGameType.ordinary,
          enabled: flag != 'enabled',
          manageEntry: flag != 'manageEntry'));
      expect(runtime.requiresGroupTenantCheck, isFalse);
      expect(runtime.featureContext.capabilities.sangong.canManage, isTrue);
      expect(runtime.http.hasTenant, isTrue);
      expect(runtime.canManage, isFalse);
      expectReadOnlyReason(
          runtime, flag == 'enabled' ? '当前群尚未启用三公运营' : '当前群未开放三公运营入口');
    });
  }

  test('registered game can operate without any public groupFeatures summary',
      () {
    final base = sangongTestContext(api);
    final context = GroupFeatureContext(
      groupID: base.groupID,
      groupName: base.groupName,
      currentUserID: base.currentUserID,
      gameType: GroupGameType.sangong,
      api: base.api,
      accountPrivilege: base.privilege,
      capabilities: base.capabilities,
      sessionCurrent: base.sessionCurrent,
      capabilitiesCurrent: base.capabilitiesCurrent,
      onFeaturesChanged: base.onFeaturesChanged,
    );
    final runtime = runtimeFor(context);
    expect(context.features.valid, isFalse);
    expect(context.features.sangong.enabled, isFalse);
    expect(context.features.sangong.manageEntry, isFalse);
    expect(runtime.groupTenantReady, isTrue);
    expect(runtime.canManage, isTrue);
    expectReadOnlyReason(runtime, null);
  });

  test('current-game management migration preserves public agent conditions',
      () {
    final runtime = runtimeFor(sangongTestContext(api, enabled: false));
    expect(runtime.canManage, isTrue);
    expect(runtime.featureContext.capabilities.sangong.canOpenAgent, isTrue);
    expect(runtime.canOpenAgent, isFalse);
    expect(runtime.canViewRebateHistory, isFalse);
    expectReadOnlyReason(runtime, null);
  });

  test(
      'account default for another group cannot change the confirmed current binding',
      () async {
    final runtime = runtimeFor(sangongTestContext(api));
    await runtime.config.applySaved(_ownerConfig.copyWith(
        imGroupGameId: 'other-betting-group', tenantId: 'other-tenant'));
    expect(runtime.config.config.imGroupGameId, 'other-betting-group');
    expect(runtime.groupTenant.state!.config!.imGroupGameId, 'group-sangong');
    expect(runtime.canManage, isTrue);
    expect(runtime.http.tenantId, 'tenant-authorized');
    expectReadOnlyReason(runtime, null);
  });

  test('account default configs never confirm current-group registration',
      () async {
    final runtime = runtimeFor(
        sangongTestContext(api,
            canConfigure: false,
            canManage: false,
            canOpenAgent: false,
            tenantID: ''),
        confirmed: false);
    await runtime.config.applySaved(_ownerConfig.copyWith(
        configured: false, imGroupGameId: 'other-betting-group'));
    expect(runtime.groupTenant.state, isNull);
    expectReadOnlyReason(runtime, '当前群的三公租户绑定尚未确认');
    await runtime.config.applySaved(_ownerConfig.copyWith(imGroupGameId: ''));
    expect(runtime.groupTenant.state, isNull);
    expectReadOnlyReason(runtime, '当前群的三公租户绑定尚未确认');
  });

  test(
      'private caps and logical tenant cannot grant an unknown current binding',
      () {
    final runtime = runtimeFor(sangongTestContext(api), confirmed: false);
    expect(runtime.featureContext.capabilities.sangong.canManage, isTrue);
    expect(runtime.http.tenantId, 'tenant-authorized');
    expect(runtime.groupTenant.state, isNull);
    expect(runtime.groupTenantReady, isFalse);
    expect(runtime.canManage, isFalse);
    expect(runtime.canInitialize, isFalse);
    expectReadOnlyReason(runtime, '当前群的三公租户绑定尚未确认');
  });

  test(
      'invalidating a verified binding blocks operations until it is confirmed again',
      () {
    final runtime = runtimeFor(sangongTestContext(api));
    final verified = runtime.groupTenant.state!;
    expect(runtime.canManage, isTrue);
    runtime.groupTenant.invalidate();
    expect(runtime.canManage, isFalse);
    expect(runtime.http.tenantId, 'tenant-authorized');
    expect(runtime.canInitialize, isFalse);
    expectReadOnlyReason(runtime, '当前群的三公租户绑定尚未确认');

    runtime.groupTenant.applySaved(verified);
    expect(runtime.canManage, isTrue);
    expectReadOnlyReason(runtime, null);
  });

  for (final (status, message) in [
    (SangongGroupTenantStatus.notFound, '当前群尚未配置三公'),
    (SangongGroupTenantStatus.disabled, '当前群的三公已停用'),
    (SangongGroupTenantStatus.accessDenied, '当前群已配置三公，请联系配置者授权'),
  ]) {
    test('verified $status is distinct from an unknown binding', () {
      final runtime = runtimeFor(sangongTestContext(api), confirmed: false);
      runtime.groupTenant.applySaved(SangongGroupTenantState(
          status: status, tenantId: 'group-sangong', message: message));
      expect(runtime.groupTenantReady, isFalse);
      expect(runtime.canManage, isFalse);
      expect(
          runtime.canInitialize, status == SangongGroupTenantStatus.notFound);
      expectReadOnlyReason(runtime, message);
    });
  }

  test('a configured wire tenant cannot replace missing logical binding', () {
    final runtime = runtimeFor(
        sangongTestContext(api,
            canConfigure: false, canOpenAgent: false, tenantID: ''),
        configuredTenantId: 'wire-tenant');
    expect(runtime.http.requestTenantId, 'wire-tenant');
    expect(runtime.http.tenantId, isNull);
    expect(runtime.canManage, isFalse);
    expectReadOnlyReason(runtime, '当前群的三公租户绑定尚未确认');
    expect(runtime.http.tenantId, isNull);
  });

  for (final dimension in ['session', 'capabilities']) {
    test('$dimension invalidation takes priority over cached binding diagnosis',
        () async {
      var current = true;
      final runtime = runtimeFor(sangongTestContext(api,
          enabled: false,
          canManage: false,
          current: dimension == 'session' ? () => current : () => true,
          capabilitiesCurrent:
              dimension == 'capabilities' ? () => current : () => true));
      await runtime.config.applySaved(
          _ownerConfig.copyWith(imGroupGameId: 'other-betting-group'));
      current = false;
      expect(runtime.isCurrent, isFalse);
      expectReadOnlyReason(runtime, '账号或群上下文已变化，请重新进入');
    });
  }

  test('revoked unassigned account privilege never restores management binding',
      () async {
    final runtime = runtimeFor(sangongTestContext(api, canOpenAgent: false));
    await runtime.config.applySaved(_ownerConfig);
    api.privilege.setAllowed(false);
    expect(runtime.canManage, isFalse);
    expect(runtime.config.hasCachedConfig, isFalse);
    expect(runtime.http.tenantId, isNull);
    expectReadOnlyReason(runtime, '当前账号没有三公特权');
  });

  test('disposed runtime remains unavailable without reading disposed binding',
      () {
    final runtime = runtimeFor(sangongTestContext(api));
    runtime.dispose();
    expect(runtime.manageUnavailableReason, '账号或群上下文已变化，请重新进入');
    expect(runtime.canManage, isFalse);
    expect(api.calls, isEmpty);
  });

  test('binding diagnostics are optional for existing positional calls', () {
    final logs = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previousPrint);
    final context = sangongTestContext(api,
        enabled: false, manageEntry: false, canManage: false);
    final runtime = runtimeFor(context);
    SangongApiDebugLog.permissionDenied(
        context, runtime.manageUnavailableReason!);
    final payload = _permissionPayload(logs);
    expect(payload['reason'], '当前账号没有该群的三公运营权限');
    expect((payload['sangong'] as Map)['canManage'], isFalse);
    expect((payload['groupFeatures'] as Map)['enabled'], isFalse);
    expect((payload['groupFeatures'] as Map)['manageEntry'], isFalse);
    expect(payload.containsKey('logicalTenantId'), isFalse);
    expect(payload.containsKey('myConfig'), isFalse);
    expect(api.calls, isEmpty);
  });

  test('binding diagnostics retain config and parsed caps with secret masking',
      () {
    final logs = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previousPrint);
    final context = sangongTestContext(api,
        enabled: false, manageEntry: false, canManage: false);
    final runtime = runtimeFor(context);
    final config = {
      ..._ownerConfig.toJson(),
      'imToken': 'config-im-secret',
    };
    final original = jsonEncode(config);
    SangongApiDebugLog.permissionDenied(
        context, runtime.manageUnavailableReason!,
        logicalTenantId: '', config: config);
    final payload = _permissionPayload(logs);
    expect(payload['reason'], '当前账号没有该群的三公运营权限');
    expect(payload['logicalTenantId'], '');
    expect((payload['myConfig'] as Map)['configured'], isTrue);
    expect((payload['myConfig'] as Map)['myRole'], 'owner');
    expect((payload['myConfig'] as Map)['imGroupGameId'], 'group-sangong');
    expect((payload['myConfig'] as Map)['imToken'], '***');
    expect((payload['sangong'] as Map)['canManage'], isFalse);
    expect((payload['groupFeatures'] as Map)['enabled'], isFalse);
    expect((payload['groupFeatures'] as Map)['manageEntry'], isFalse);
    expect(logs.join(), isNot(contains('config-im-secret')));
    expect(jsonEncode(config), original);
    expect(context.capabilities.sangong.canManage, isFalse);
    expect(api.calls, isEmpty);
  });
}
