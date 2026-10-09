import 'services/authorization/sangong_access_policy.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/group_feature_context.dart';
import 'api/diagnostics/sangong_api_debug_log.dart';
import 'api/sangong_admin_api.dart';
import 'api/sangong_agent_api.dart';
import 'api/sangong_api_config.dart';
import 'api/sangong_game_http.dart';
import 'api/sangong_reports_api.dart';
import 'api/sangong_settings_api.dart';
import 'models/agent_rebate_models.dart';
import 'models/sangong_my_config.dart';
import 'models/binding/sangong_group_tenant_state.dart';
import 'services/authorization/sangong_operation_scope.dart';
import 'services/binding/sangong_group_tenant_store.dart';
import 'services/sangong_realtime.dart';
import 'widgets/authorization/privilege_route_guard.dart';

class SangongRuntime extends ChangeNotifier {
  SangongRuntime(this.featureContext,
      {String? baseUrl,
      String? configuredTenantId,
      this.selectedAgentTenantId,
      this.selectedAgentHallName,
      String pathPrefix = SangongApiConfig.pathPrefix}) {
    http = SangongGameHttp(featureContext,
        baseUrl: baseUrl,
        configuredTenantId: configuredTenantId,
        pathPrefix: pathPrefix);
    admin = SangongAdminApi(http);
    agent = AgentRebateApi(http);
    reports = SangongReportsApi(http);
    config = SangongConfigStore(this);
    groupTenant = SangongGroupTenantStore(
        readContext: () => featureContext,
        isCurrent: () => isCurrent && isPrivileged,
        onChanged: _notifyContextChanged);
    settings = SangongSettingsApi(http, mayEdit: () => canManage);
    realtime = SangongRealtime(this);
    featureContext.privilege.addListener(_privilegeChanged);
    _applyCapabilities();
  }
  GroupFeatureContext featureContext;
  final String? selectedAgentTenantId, selectedAgentHallName;
  late final SangongGameHttp http;
  late final SangongAdminApi admin;
  late final AgentRebateApi agent;
  late final SangongReportsApi reports;
  late final SangongConfigStore config;
  late final SangongGroupTenantStore groupTenant;
  late final SangongSettingsApi settings;
  late final SangongRealtime realtime;
  bool _disposed = false;
  bool _contextNotificationQueued = false;
  AgentEntryContextDto? agentContext;
  String? preferredAgentHallId;
  bool get isSessionCurrent => !_disposed && featureContext.sessionCurrent();
  bool get isCurrent =>
      isSessionCurrent && featureContext.capabilitiesCurrent();
  bool get canConfigure =>
      isCurrent &&
      isPrivileged &&
      (featureContext.capabilities.sangong.canConfigure || canInitialize);
  bool get requiresGroupTenantCheck {
    if (featureContext.gameType != GroupGameType.sangong) return false;
    final capability = featureContext.capabilities.sangong;
    final agentOnly = capability.canOpenAgent &&
        !capability.canConfigure &&
        !capability.canManage &&
        (capability.requiresTenantSelection ||
            capability.tenantID.isNotEmpty &&
                capability.tenantID != featureContext.groupID);
    return !agentOnly;
  }

  bool get canInitialize =>
      isCurrent &&
      isPrivileged &&
      requiresGroupTenantCheck &&
      featureContext.isGroupAdmin &&
      !groupTenant.loading &&
      groupTenant.error == null &&
      groupTenant.state?.status == SangongGroupTenantStatus.notFound;

  bool get groupTenantReady =>
      !requiresGroupTenantCheck ||
      (groupTenant.error == null &&
          !groupTenant.loading &&
          groupTenant.state?.status == SangongGroupTenantStatus.configured);
  bool get isPrivileged => featureContext.privilege.allows(
      userID: featureContext.currentUserID,
      baseUrl: featureContext.api.baseUrl);
  bool get canManage =>
      isCurrent &&
      isPrivileged &&
      groupTenantReady &&
      (requiresGroupTenantCheck ||
          (featureContext.features.sangong.enabled &&
              featureContext.features.sangong.manageEntry)) &&
      http.hasTenant &&
      featureContext.capabilities.sangong.canManage;

  /// Explains existing readiness without changing permissions or binding state.
  String? get manageUnavailableReason {
    if (canManage) return null;
    if (!isCurrent) return '账号或群上下文已变化，请重新进入';
    if (!isPrivileged) return '当前账号没有三公特权';
    if (requiresGroupTenantCheck) {
      if (groupTenant.error != null) return '当前群三公配置暂时无法确认，请重试';
      if (groupTenant.loading || groupTenant.state == null) {
        return '当前群的三公租户绑定尚未确认';
      }
      final registration = groupTenant.state;
      if (registration != null &&
          registration.status != SangongGroupTenantStatus.configured) {
        return registration.message;
      }
    }
    final saved = groupTenant.state?.config;
    if (requiresGroupTenantCheck &&
        saved != null &&
        saved.configured &&
        saved.imGroupGameId.isNotEmpty &&
        saved.imGroupGameId != featureContext.groupID) {
      return '当前群不是三公配置中绑定的下注群';
    }
    final feature = featureContext.features.sangong;
    // Current game tenants use active from the point lookup and the aggregate
    // capability. Older SDK ex summaries may be absent or out of date.
    if (!requiresGroupTenantCheck) {
      if (!feature.enabled) return '当前群尚未启用三公运营';
      if (!feature.manageEntry) return '当前群未开放三公运营入口';
    }
    if (!featureContext.capabilities.sangong.canManage) {
      return '当前账号没有该群的三公运营权限';
    }
    if (!http.hasTenant) return '当前群的三公租户绑定尚未确认';
    return '当前群暂不可进行三公运营';
  }

  bool get canOpenAgent =>
      isCurrent &&
      canAccessModule &&
      http.hasTenant &&
      featureContext.capabilities.sangong.canOpenAgent;
  bool get canViewRebateHistory =>
      canOpenAgent && featureContext.capabilities.sangong.canViewRebateHistory;
  bool get canManageMembers =>
      canManage &&
      (featureContext.capabilities.sangong.raw['canManageMembers'] == true ||
          (requiresGroupTenantCheck
              ? groupTenant.state?.config?.canManageMembers == true
              : config.config.canManageMembers));
  String get preferenceKey =>
      '${featureContext.api.baseUrl}:${featureContext.currentUserID}:${featureContext.groupID}';
  bool get canAccessModule => sangongModuleAccess(featureContext);
  void _applyCapabilities() {
    if (!canAccessModule) return;
    final capability = featureContext.capabilities.sangong;
    if (selectedAgentTenantId != null && capability.canOpenAgent) {
      http.setTenantId(selectedAgentTenantId);
      return;
    }
    if ((capability.canManage || capability.canOpenAgent) &&
        capability.tenantID.isNotEmpty) {
      http.setTenantId(capability.tenantID);
    }
  }

  void _clearPrivateBinding() {
    config.invalidate();
    groupTenant.invalidate();
    agentContext = null;
    realtime.latestState = null;
    realtime.error = null;
    http.setTenantId(null);
  }

  void _privilegeChanged() {
    if (_disposed) return;
    if (!isPrivileged) {
      _clearPrivateBinding();
    }
    _applyCapabilities();
    notifyListeners();
  }

  void updateContext(GroupFeatureContext value) {
    final old = featureContext.capabilities.sangong;
    final next = value.capabilities.sangong;
    if (featureContext.gameType != value.gameType) groupTenant.invalidate();
    if (!identical(featureContext.privilege, value.privilege) ||
        featureContext.currentUserID != value.currentUserID ||
        featureContext.groupID != value.groupID ||
        featureContext.api != value.api ||
        featureContext.capabilities.version != value.capabilities.version ||
        old.canConfigure != next.canConfigure ||
        old.canManage != next.canManage ||
        old.canOpenAgent != next.canOpenAgent ||
        old.requiresTenantSelection != next.requiresTenantSelection ||
        old.tenantID != next.tenantID) {
      _clearPrivateBinding();
    }
    if (!identical(featureContext.privilege, value.privilege)) {
      featureContext.privilege.removeListener(_privilegeChanged);
      value.privilege.addListener(_privilegeChanged);
    }
    featureContext = value;
    http.context = value;
    if (!canAccessModule) _clearPrivateBinding();
    _applyCapabilities();
    _notifyContextChanged();
  }

  void _notifyContextChanged() {
    // Chat updates this runtime while rebuilding its host. Other routes may
    // listen to the same runtime, so notify them after this build completes.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_contextNotificationQueued) return;
      _contextNotificationQueued = true;
      scheduleMicrotask(() {
        _contextNotificationQueued = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  Future<void> ensureManageBinding() async {
    if (!isCurrent) throw StateError('账号或群上下文已变化，请重新进入');
    if (!isPrivileged) throw StateError('当前账号没有三公特权');
    if (requiresGroupTenantCheck) {
      final registration = await groupTenant.refresh();
      if (!isCurrent || !isPrivileged) {
        throw StateError('账号或群上下文已变化，请重新进入');
      }
      if (registration.config != null) {
        final verified = featureContext.capabilities.sangong.tenantID;
        http.setTenantId(
            verified.isNotEmpty ? verified : registration.tenantId);
      }
      return;
    }
    if (canManage) return;
    if (!canConfigure && !featureContext.capabilities.sangong.canManage) {
      SangongApiDebugLog.permissionDenied(featureContext, '没有当前群的三公配置或运营权限');
      throw StateError('没有当前群的三公配置或运营权限');
    }
    throw StateError('当前群的三公运营绑定尚未确认');
  }

  Future<void> ensureAgentBinding() async {
    if (!isCurrent ||
        !canAccessModule ||
        !featureContext.capabilities.sangong.canOpenAgent) {
      throw StateError('没有当前群的三公代理权限');
    }
    if (canOpenAgent) return;
    final scope = SangongOperationScope.capture(featureContext, http.tenantId);
    final entry = await agent.fetchEntryContext(featureContext.groupID);
    if (!isCurrent ||
        !canAccessModule ||
        !scope.matches(featureContext, http.tenantId)) {
      throw StateError('账号或群上下文已变化，请重新进入');
    }
    if (!entry.showAgentEntry ||
        entry.tenantId.isEmpty ||
        (entry.agentImGroupId.isNotEmpty &&
            entry.agentImGroupId != featureContext.groupID)) {
      throw StateError('当前账号在该群没有代理数据');
    }
    agentContext = entry;
    http.setTenantId(entry.tenantId);
    notifyListeners();
  }

  void changed() {
    if (isCurrent) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    groupTenant.invalidate();
    featureContext.privilege.removeListener(_privilegeChanged);
    // Covered profile routes must drop private cached content before teardown.
    notifyListeners();
    realtime.dispose();
    http.dispose();
    super.dispose();
  }
}

class SangongConfigStore {
  SangongConfigStore(this.runtime);
  final SangongRuntime runtime;
  SangongMyConfig? _cached;
  DateTime? _fetched;
  Future<SangongMyConfig>? _pending;
  int _revision = 0;
  SangongMyConfig get config => _cached ?? const SangongMyConfig();
  bool get hasCachedConfig => _cached != null;
  Future<SangongMyConfig> refreshFromNetwork({bool force = false}) {
    if (!runtime.isCurrent || !runtime.isPrivileged) {
      return Future.error(StateError('当前账号没有三公特权'));
    }
    final pending = _pending;
    if (pending != null) return pending;
    if (!force &&
        _cached != null &&
        _fetched != null &&
        DateTime.now().difference(_fetched!) < const Duration(minutes: 5)) {
      return Future.value(_cached);
    }
    final revision = _revision;
    final context = runtime.featureContext;
    final privilege = context.privilege;
    final privilegeRevision = privilege.revision;
    late final Future<SangongMyConfig> task;
    task = runtime.admin.fetchMyConfig().then((value) async {
      if (!runtime.isCurrent || !runtime.isPrivileged) {
        throw StateError('账号或群上下文已变化，请重新进入');
      }
      if (!identical(privilege, runtime.featureContext.privilege) ||
          privilegeRevision != runtime.featureContext.privilege.revision) {
        throw StateError('账号特权已变化，请重新进入');
      }
      if (revision != _revision) return config;
      await applySaved(value);
      return value;
    }).catchError((Object error, StackTrace stack) {
      // A save may confirm the tenant while an older read is still in flight.
      // Reuse only that newer cache in the same authorized context; context
      // invalidation clears the cache and must retain the original failure.
      final cached = _cached;
      if (runtime.isCurrent &&
          runtime.isPrivileged &&
          identical(privilege, runtime.featureContext.privilege) &&
          privilegeRevision == runtime.featureContext.privilege.revision &&
          identical(context, runtime.featureContext) &&
          revision != _revision &&
          cached != null) {
        return cached;
      }
      Error.throwWithStackTrace(error, stack);
    }).whenComplete(() {
      if (identical(_pending, task)) _pending = null;
    });
    _pending = task;
    return task;
  }

  void invalidate() {
    _revision++;
    _cached = null;
    _fetched = null;
    _pending = null;
  }

  Future<void> applySaved(SangongMyConfig value) async {
    if (!runtime.isCurrent || !runtime.isPrivileged) return;
    _revision++;
    _cached = value;
    _fetched = DateTime.now();
    if ((runtime.canConfigure ||
            runtime.featureContext.capabilities.sangong.canManage) &&
        value.configured &&
        value.imGroupGameId == runtime.featureContext.groupID &&
        value.tenantId.isNotEmpty &&
        (value.isOwner || value.isAdmin || value.canEditConfig)) {
      runtime.http.setTenantId(value.tenantId);
    }
    runtime.changed();
  }
}

class AgentSessionSnapshot {
  AgentSessionSnapshot(this.runtime)
      : _scope = SangongOperationScope.capture(
            runtime.featureContext, runtime.http.tenantId);
  final SangongRuntime runtime;
  final SangongOperationScope _scope;
  bool get isCurrent =>
      runtime.isCurrent &&
      _scope.matches(runtime.featureContext, runtime.http.tenantId);
}

class SangongScope extends InheritedNotifier<SangongRuntime> {
  const SangongScope(
      {super.key, required SangongRuntime runtime, required super.child})
      : super(notifier: runtime);
  static SangongRuntime read(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<SangongScope>();
    final scope = element?.widget as SangongScope?;
    if (scope?.notifier == null) {
      throw StateError('Sangong page requires SangongScope');
    }
    return scope!.notifier!;
  }
}

/// Captures the scoped APIs across Navigator routes, including initState.
class SangongPageRoute<T> extends MaterialPageRoute<T> {
  SangongPageRoute(
      {required BuildContext context,
      required WidgetBuilder builder,
      bool agent = false,
      super.settings,
      super.fullscreenDialog})
      : super(builder: _capture(context, builder, agent));
  static WidgetBuilder _capture(
      BuildContext context, WidgetBuilder builder, bool agent) {
    final runtime = SangongScope.read(context);
    final featureContext = runtime.featureContext;
    final scope =
        SangongOperationScope.capture(featureContext, runtime.http.tenantId);
    return (_) => SangongPrivilegeRouteGuard(
          featureContext: featureContext,
          allowAssignedAgent: agent,
          scopeChanges: runtime,
          isCurrent: () =>
              runtime.isCurrent &&
              scope.matches(runtime.featureContext, runtime.http.tenantId) &&
              (!agent || runtime.canOpenAgent),
          builder: (_) =>
              SangongScope(runtime: runtime, child: Builder(builder: builder)),
        );
  }
}
