import 'dart:async';
import 'package:flutter/material.dart';
import '../models/group_feature_context.dart';
import 'sangong_scope.dart';
import 'api/diagnostics/sangong_api_debug_log.dart';
import 'api/sangong_admin_api.dart';
import 'api/sangong_api_config.dart';
import 'models/sangong_admin_models.dart';
import 'models/binding/sangong_group_tenant_state.dart';
import 'pages/authorization/sangong_operator_unavailable_page.dart';
import 'pages/sangong_game_rules_settings_page.dart';
import 'pages/sangong_manage_home_page.dart';
import 'pages/sangong_my_config_page.dart';
import 'pages/sangong_agent_dashboard_page.dart';
import 'pages/sangong_agent_team_page.dart';
import 'pages/sangong_agent_personal_page.dart';
import 'services/group_game_prefs.dart';
import 'support/settings_exports.dart';
import 'support/sangong_ui.dart';
import 'widgets/group_game_status_banner.dart';
import 'widgets/group_game_floating_entry.dart';
import 'widgets/sangong_agent_floating_entry.dart';
import 'widgets/sangong_bet_preview_sheet.dart';
import 'widgets/sangong_round_settle_flow.dart';
import 'widgets/authorization/privilege_route_guard.dart';
import 'utils/sangong_bet_submit_cutoff.dart';
import 'utils/sangong_report_image_messages.dart';

export 'sangong_scope.dart' show SangongScope, SangongRuntime;
export 'widgets/group_game_status_banner.dart';
export 'pages/sangong_manage_home_page.dart';
export 'pages/sangong_my_config_page.dart';
export 'pages/sangong_game_rules_settings_page.dart';
export 'pages/sangong_members_page.dart';
export 'pages/sangong_all_users_page.dart';
export 'pages/sangong_agent_dashboard_page.dart';
export 'pages/sangong_agent_team_page.dart';
export 'pages/sangong_agent_personal_page.dart';

typedef SangongHostBuilder = Widget Function(
    BuildContext context, Widget statusBanner, Widget overlay);

/// A single owner for both top status and original draggable native controls.
/// The builder lets the chat reserve banner height while placing the overlay
/// in its bounded body Stack. The default also requires bounded dimensions.
class SangongFeatureHost extends StatefulWidget {
  const SangongFeatureHost(
      {super.key,
      required this.featureContext,
      this.builder,
      this.pathPrefix = SangongApiConfig.pathPrefix});
  final GroupFeatureContext featureContext;
  final SangongHostBuilder? builder;
  final String pathPrefix;
  @override
  State<SangongFeatureHost> createState() => _SangongFeatureHostState();
}

class _SangongFeatureHostState extends State<SangongFeatureHost> {
  late SangongRuntime _runtime;
  StreamSubscription<Map<String, dynamic>>? _events;
  String? _error;
  bool _busy = false, _floatVisible = true, _subscribed = false;
  int _loadGeneration = 0;
  Future<void>? _activeLoad;
  bool _reloadQueued = false;
  bool _lastPrivileged = false;
  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    _runtime =
        SangongRuntime(widget.featureContext, pathPrefix: widget.pathPrefix);
    _lastPrivileged = _runtime.isPrivileged;
    _runtime.addListener(_changed);
    _runtime.realtime.addListener(_changed);
    _events = widget.featureContext.events.listen((event) {
      if (!_runtime.isCurrent ||
          !_runtime.isPrivileged ||
          event['groupID'] != widget.featureContext.groupID) {
        return;
      }
      final kind = event['key'] ?? event['action'];
      if (kind == 'groupGameChanged') {
        unawaited(_runtime.realtime.refreshSnapshot());
      }
      if (kind == 'groupFeatureCapabilitiesChanged') unawaited(_load());
    });
    unawaited(_load());
  }

  void _changed() {
    if (!mounted) return;
    final privileged = _runtime.isPrivileged;
    final restored = privileged && !_lastPrivileged;
    _lastPrivileged = privileged;
    if (!privileged) {
      _loadGeneration++;
      _error = null;
    }
    final shouldSubscribe = _runtime.canManage;
    if (shouldSubscribe && !_subscribed) {
      _subscribed = true;
      _runtime.realtime.acquire();
    } else if (!shouldSubscribe && _subscribed) {
      _subscribed = false;
      _runtime.realtime.release();
    }
    setState(() {});
    if (restored) unawaited(_load());
  }

  Future<void> _load() async {
    final pending = _activeLoad;
    if (pending != null) {
      _reloadQueued = true;
      return pending;
    }
    late final Future<void> task;
    task = _loadPass().whenComplete(() {
      if (!identical(_activeLoad, task)) return;
      _activeLoad = null;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        unawaited(_load());
      }
    });
    _activeLoad = task;
    return task;
  }

  Future<void> _loadPass() async {
    final generation = ++_loadGeneration;
    final runtime = _runtime;
    if (!runtime.isCurrent || !runtime.isPrivileged) return;
    try {
      final visible =
          await GroupGamePrefs.instance.isFloatVisible(runtime.preferenceKey);
      if (!mounted ||
          generation != _loadGeneration ||
          !runtime.isCurrent ||
          !runtime.isPrivileged) {
        return;
      }
      setState(() => _floatVisible = visible);
      final capabilities = widget.featureContext.capabilities.sangong;
      if (runtime.requiresGroupTenantCheck ||
          capabilities.canConfigure ||
          capabilities.canManage) {
        await runtime.ensureManageBinding();
      }
      if (capabilities.canOpenAgent &&
          widget.featureContext.features.sangong.agentEntry) {
        await runtime.ensureAgentBinding();
      }
      if (!mounted ||
          generation != _loadGeneration ||
          !runtime.isCurrent ||
          !runtime.isPrivileged) {
        return;
      }
      _error = null;
      _floatVisible = visible;
      _changed();
    } catch (failure) {
      if (!mounted ||
          generation != _loadGeneration ||
          !runtime.isCurrent ||
          !runtime.isPrivileged) {
        return;
      }
      setState(() => _error = DioErrorMessage.forApp(failure));
    }
  }

  Future<void> _retry() async {
    if (!_runtime.groupTenantReady) _runtime.groupTenant.invalidate();
    await _load();
    if (mounted && _runtime.canManage && _subscribed) {
      await _runtime.realtime.refreshSnapshot();
    }
  }

  void _destroy() {
    _loadGeneration++;
    _activeLoad = null;
    _reloadQueued = false;
    _events?.cancel();
    _events = null;
    _runtime.removeListener(_changed);
    _runtime.realtime.removeListener(_changed);
    _runtime.dispose();
    _subscribed = false;
  }

  @override
  void didUpdateWidget(SangongFeatureHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.featureContext.groupID != widget.featureContext.groupID ||
        oldWidget.featureContext.currentUserID !=
            widget.featureContext.currentUserID ||
        oldWidget.featureContext.api != widget.featureContext.api ||
        oldWidget.pathPrefix != widget.pathPrefix) {
      _destroy();
      _create();
    } else {
      final oldContext = _runtime.featureContext;
      final old = oldContext.capabilities.sangong;
      final next = widget.featureContext.capabilities.sangong;
      final changed = oldContext.capabilities.version !=
              widget.featureContext.capabilities.version ||
          oldContext.gameType != widget.featureContext.gameType ||
          old.canConfigure != next.canConfigure ||
          old.canManage != next.canManage ||
          old.canOpenAgent != next.canOpenAgent ||
          old.tenantID != next.tenantID ||
          oldContext.features.sangong.enabled !=
              widget.featureContext.features.sangong.enabled ||
          oldContext.features.sangong.manageEntry !=
              widget.featureContext.features.sangong.manageEntry ||
          oldContext.features.sangong.agentEntry !=
              widget.featureContext.features.sangong.agentEntry;
      final runtime = _runtime;
      final value = widget.featureContext;
      scheduleMicrotask(() {
        if (!mounted ||
            !identical(_runtime, runtime) ||
            !identical(widget.featureContext, value)) {
          return;
        }
        runtime.updateContext(value);
        if (changed) unawaited(_load());
      });
    }
  }

  @override
  void dispose() {
    _destroy();
    super.dispose();
  }

  Future<void> _report(
      BuildContext context,
      Future<SangongReportImageResult> Function(SangongAdminApi api)
          request) async {
    if (_busy) return;
    final runtime = _runtime;
    _busy = true;
    AppHudSession? hud;
    try {
      if (!await _prepareOperatorAction(context, runtime) ||
          !context.mounted ||
          !_operatorActionCurrent(runtime)) {
        return;
      }
      hud = AppHud.begin();
      final result = await request(runtime.admin);
      if (!context.mounted || !_operatorActionCurrent(runtime)) return;
      if (!result.ok || !(result.sent || result.queued)) {
        throw StateError(
            result.message.isNotEmpty ? result.message : '报表发送尚未确认，请刷新后查看');
      }
      await hud.end();
      if (!context.mounted || !_operatorActionCurrent(runtime)) return;
      ToastUtils.toast(
          sangongReportImageSuccessToast(AppI18n.of(context), result,
              fallbackZhHans: '已发送', fallbackZhHant: '已發送', fallbackEn: 'Sent'),
          context: context);
    } catch (failure) {
      await hud?.end();
      if (context.mounted && _operatorActionCurrent(runtime)) {
        ToastUtils.toast(DioErrorMessage.forApp(failure), context: context);
      }
    } finally {
      await hud?.end();
      _busy = false;
    }
  }

  Future<void> _cutoff(BuildContext context) async {
    if (_busy) return;
    final runtime = _runtime;
    _busy = true;
    try {
      if (!await _prepareOperatorAction(context, runtime) ||
          !context.mounted ||
          !_operatorActionCurrent(runtime)) {
        return;
      }
      final session = await runtime.admin.fetchSession();
      if (!context.mounted || !_operatorActionCurrent(runtime)) return;
      final round = session.round;
      if (round == null || round.id <= 0) throw StateError('当前没有可截止的游戏局');
      final result = await runtime.admin.previewBets(roundId: round.id);
      if (!context.mounted || !_operatorActionCurrent(runtime)) return;
      final submitted = await SangongBetPreviewSheet.show(context,
          preview: result.preview,
          cutoff: const SangongBetSubmitCutoff(),
          roundId: round.id,
          doorCount: runtime.realtime.latestState?.doorCount ?? 6,
          bankerName: round.bankerNickname,
          bankerDoor: round.bankerDoor);
      if (submitted != null &&
          context.mounted &&
          _operatorActionCurrent(runtime)) {
        await runtime.realtime.refreshSnapshot();
      }
    } catch (failure) {
      if (context.mounted && _operatorActionCurrent(runtime)) {
        ToastUtils.toast(DioErrorMessage.forApp(failure), context: context);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _settle(BuildContext context) async {
    if (_busy) return;
    final runtime = _runtime;
    _busy = true;
    try {
      if (!await _prepareOperatorAction(context, runtime) ||
          !context.mounted ||
          !_operatorActionCurrent(runtime)) {
        return;
      }
      await SangongRoundSettleFlow.run(context);
      if (context.mounted && _operatorActionCurrent(runtime)) {
        await runtime.realtime.refreshSnapshot();
      }
    } finally {
      _busy = false;
    }
  }

  bool _operatorActionCurrent(SangongRuntime runtime) =>
      mounted &&
      identical(_runtime, runtime) &&
      runtime.canManage &&
      runtime.groupTenantReady;

  Future<bool> _prepareOperatorAction(
      BuildContext context, SangongRuntime runtime) async {
    bool current() =>
        mounted &&
        context.mounted &&
        identical(_runtime, runtime) &&
        runtime.isSessionCurrent &&
        runtime.isPrivileged;
    if (!current()) return false;
    if (runtime.canManage && runtime.groupTenantReady) return true;
    try {
      final next = await SangongApiDebugLog.trace(
          () => runtime.featureContext.refreshCapabilities(force: true));
      if (!context.mounted || !current()) return false;
      runtime.updateContext(next);
      await runtime.ensureManageBinding();
      if (!context.mounted || !current()) return false;
      if (runtime.canManage && runtime.groupTenantReady) return true;
      if (runtime.groupTenant.state?.status ==
          SangongGroupTenantStatus.notFound) {
        await _openManage(context);
        return false;
      }
      final reason = runtime.manageUnavailableReason ?? '当前群暂不可进行三公运营';
      _logManageUnavailable(runtime, reason);
      ToastUtils.toast(reason, context: context);
    } catch (failure) {
      if (context.mounted && current()) {
        final reason = DioErrorMessage.forApp(failure);
        _logManageUnavailable(runtime, reason);
        ToastUtils.toast(reason, context: context);
      }
    }
    return false;
  }

  Future<void> _openRules(BuildContext context) async {
    if (_busy) return;
    final runtime = _runtime;
    _busy = true;
    try {
      if (!await _prepareOperatorAction(context, runtime) ||
          !context.mounted ||
          !_operatorActionCurrent(runtime)) {
        return;
      }
      await SangongGameRulesSettingsPage.open(context,
          floatVisible: _floatVisible, onFloatVisibleChanged: _visibility);
    } catch (failure) {
      if (context.mounted && _operatorActionCurrent(runtime)) {
        ToastUtils.toast(DioErrorMessage.forApp(failure), context: context);
      }
    } finally {
      _busy = false;
    }
  }

  void _visibility(bool value) {
    if (!mounted) return;
    setState(() => _floatVisible = value);
    unawaited(
        GroupGamePrefs.instance.setFloatVisible(_runtime.preferenceKey, value));
  }

  Future<void> _openManage(BuildContext context) =>
      SangongModule.openManage(context,
          featureContext: widget.featureContext,
          runtime: _runtime,
          floatVisible: _floatVisible,
          onFloatVisibleChanged: _visibility);

  Future<void> _openAgent(BuildContext context, String section) =>
      SangongModule.openAgent(context,
          featureContext: widget.featureContext,
          runtime: _runtime,
          section: section);

  @override
  Widget build(BuildContext context) => SangongScope(
      runtime: _runtime,
      child: Builder(builder: (scopeContext) {
        final state = _runtime.realtime.latestState;
        final registration = _runtime.groupTenant.state;
        final bindingStatus = _runtime.requiresGroupTenantCheck
            ? (_runtime.groupTenant.loading
                ? '正在确认当前群的三公配置'
                : registration != null &&
                        registration.status !=
                            SangongGroupTenantStatus.configured &&
                        registration.status != SangongGroupTenantStatus.notFound
                    ? registration.message
                    : null)
            : null;
        final status = _error ?? bindingStatus ?? _runtime.realtime.error;
        Widget banner = const SizedBox.shrink();
        if (_floatVisible && state != null && _runtime.canManage) {
          // Match 99chat: keep the last valid game banner during reconnects.
          banner = GroupGameStatusBanner(
              key: const ValueKey('sangong-status-banner'),
              doorCount: state.doorCount,
              roundStatus: state.toGroupGameRoundStatus());
        } else if (_floatVisible &&
            _runtime.isPrivileged &&
            status != null &&
            (_runtime.requiresGroupTenantCheck ||
                _runtime.canConfigure ||
                widget.featureContext.capabilities.sangong.canManage)) {
          banner = Material(
              color: AppColors.card(dark: settingsIsDark(context)),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    Expanded(
                        child: Text(status,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.subText(
                                    dark: settingsIsDark(context))))),
                    TextButton(
                        key: const ValueKey('sangong-host-retry'),
                        onPressed: _retry,
                        child: const Text('重试'))
                  ])));
        }
        final setupOnly = _runtime.requiresGroupTenantCheck &&
            !_runtime.groupTenant.loading &&
            _runtime.groupTenant.error == null &&
            registration?.status == SangongGroupTenantStatus.notFound;
        final overlay = LayoutBuilder(
            builder: (context, constraints) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    size: constraints.biggest,
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero),
                child: Stack(fit: StackFit.expand, children: [
                  if (widget.featureContext.gameType == GroupGameType.sangong &&
                      _floatVisible &&
                      _runtime.isCurrent &&
                      _runtime.isPrivileged &&
                      (setupOnly || _runtime.canManage))
                    GroupGameFloatingEntry(
                        key: ValueKey(
                            'sangong-operator-${widget.featureContext.groupID}'),
                        theme: SangongFloatTheme.of(context),
                        conversationId: _runtime.preferenceKey,
                        setupOnly: setupOnly,
                        settleActionLabel: state?.round?.canVoidResettle == true
                            ? SangongRoundSettleFlow.lastSettledCaption(
                                scopeContext, AppI18n.of(context))
                            : null,
                        onOpenSetup: () => unawaited(_openManage(scopeContext)),
                        onOpenCutoff: () => unawaited(_cutoff(scopeContext)),
                        onOpenSettle: () => unawaited(_settle(scopeContext)),
                        onSendSettleImage: () => unawaited(_report(
                            scopeContext,
                            (api) => api.sendSettleReportImage(
                                roundId: 0))),
                        onSendSettleBill: () => unawaited(_report(
                            scopeContext,
                            (api) => api.sendSettleBillImage(
                                roundId: 0))),
                        onSendPointsImage: () => unawaited(
                            _report(scopeContext, (api) => api.sendPointsReportImage())),
                        onSendTrendImage: () => unawaited(_report(scopeContext, (api) => api.sendTrendReportImage())),
                        onOpenRulesSettings: () => unawaited(_openRules(scopeContext))),
                  if (widget.featureContext.gameType ==
                          GroupGameType.sangongAgent &&
                      _runtime.isSessionCurrent &&
                      _runtime.isPrivileged)
                    SangongAgentFloatingEntry(
                        key: ValueKey(
                            'sangong-agent-${widget.featureContext.groupID}'),
                        theme: SangongFloatTheme.of(context),
                        conversationId: _runtime.preferenceKey,
                        onOpenQuery: () =>
                            unawaited(_openAgent(scopeContext, 'team')),
                        onOpenTeam: () =>
                            unawaited(_openAgent(scopeContext, 'dashboard')),
                        onOpenPersonal: () =>
                            unawaited(_openAgent(scopeContext, 'personal'))),
                ])));
        return widget.builder?.call(scopeContext, banner, overlay) ??
            Stack(fit: StackFit.expand, children: [
              overlay,
              Positioned(top: 0, left: 0, right: 0, child: banner)
            ]);
      }));
}

class SangongModule {
  static Future<void> openManage(BuildContext context,
          {required GroupFeatureContext featureContext,
          SangongRuntime? runtime,
          String pathPrefix = SangongApiConfig.pathPrefix,
          bool? floatVisible,
          ValueChanged<bool>? onFloatVisibleChanged}) =>
      _open(context,
          featureContext: featureContext,
          runtime: runtime,
          pathPrefix: pathPrefix,
          floatVisible: floatVisible,
          onFloatVisibleChanged: onFloatVisibleChanged,
          agent: false);
  static Future<void> openAgent(BuildContext context,
          {required GroupFeatureContext featureContext,
          SangongRuntime? runtime,
          String pathPrefix = SangongApiConfig.pathPrefix,
          String section = 'dashboard'}) =>
      _open(context,
          featureContext: featureContext,
          runtime: runtime,
          pathPrefix: pathPrefix,
          agent: true,
          section: section);
  static Future<void> _open(BuildContext context,
      {required GroupFeatureContext featureContext,
      SangongRuntime? runtime,
      required String pathPrefix,
      required bool agent,
      bool? floatVisible,
      ValueChanged<bool>? onFloatVisibleChanged,
      String section = 'dashboard'}) async {
    if (!featureContext.sessionCurrent()) return;
    final privilege = featureContext.privilege;
    final allowed = await privilege.refresh();
    if (!allowed || !context.mounted || !featureContext.sessionCurrent()) {
      return;
    }
    final current = featureContext.readCurrentContext();
    if (!current.sessionCurrent() ||
        current.currentUserID != featureContext.currentUserID ||
        current.groupID != featureContext.groupID ||
        !identical(current.api, featureContext.api) ||
        !identical(current.privilege, privilege) ||
        !privilege.allows(
            userID: current.currentUserID, baseUrl: current.api.baseUrl)) {
      return;
    }
    final nextRuntime =
        runtime ?? SangongRuntime(current, pathPrefix: pathPrefix);
    if (runtime != null) runtime.updateContext(current);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => SangongPrivilegeRouteGuard(
              featureContext: current,
              refreshOnEntry: false,
              requireCapabilitiesCurrent: false,
              scopeChanges: nextRuntime,
              isCurrent: () => nextRuntime.isSessionCurrent,
              builder: (_) => _SangongModulePage(
                  runtime: nextRuntime,
                  owned: runtime == null,
                  agent: agent,
                  floatVisible: floatVisible,
                  onFloatVisibleChanged: onFloatVisibleChanged,
                  section: section))));
    } finally {
      if (runtime == null) nextRuntime.dispose();
    }
  }
}

class _SangongModulePage extends StatefulWidget {
  const _SangongModulePage(
      {required this.runtime,
      required this.owned,
      required this.agent,
      this.floatVisible,
      this.onFloatVisibleChanged,
      required this.section});
  final SangongRuntime runtime;
  final bool owned, agent;
  final bool? floatVisible;
  final ValueChanged<bool>? onFloatVisibleChanged;
  final String section;
  @override
  State<_SangongModulePage> createState() => _SangongModulePageState();
}

class _SangongModulePageState extends State<_SangongModulePage> {
  bool _loading = true;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final entry = widget.runtime.featureContext;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Discovery is controlled by the account flag. Private data still
      // requires a freshly verified group business permission and binding.
      final current = await SangongApiDebugLog.trace(
          () => entry.refreshCapabilities(force: true));
      if (!mounted ||
          generation != _generation ||
          !widget.runtime.isSessionCurrent ||
          !widget.runtime.isPrivileged) {
        return;
      }
      widget.runtime.updateContext(current);
      if (widget.agent) {
        await widget.runtime.ensureAgentBinding();
      } else {
        await widget.runtime.ensureManageBinding();
      }
      if (!mounted ||
          generation != _generation ||
          !widget.runtime.isSessionCurrent ||
          !widget.runtime.isPrivileged) {
        return;
      }
      if (!widget.runtime.isCurrent) {
        throw StateError('群业务权限已变化，请重试');
      }
      if (!widget.agent && !widget.runtime.canManage) {
        _logManageUnavailable(widget.runtime,
            widget.runtime.manageUnavailableReason ?? '当前群暂不可进行三公运营');
      }
      setState(() => _loading = false);
    } catch (failure) {
      if (mounted &&
          generation == _generation &&
          widget.runtime.isSessionCurrent &&
          widget.runtime.isPrivileged) {
        setState(() {
          _loading = false;
          _error = DioErrorMessage.forApp(failure);
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    if (widget.owned) widget.runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SangongScope(
      runtime: widget.runtime,
      child: Builder(builder: (context) {
        if (_loading || _error != null) {
          return SettingsScaffold(
              title: widget.agent ? '三公代理' : '三公管理',
              children: [
                const SizedBox(height: 100),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Text(_error!, textAlign: TextAlign.center),
                  SettingsPrimaryButton(text: '重试', onPressed: _load)
                ]
              ]);
        }
        return SangongPrivilegeRouteGuard(
            featureContext: widget.runtime.featureContext,
            refreshOnEntry: false,
            scopeChanges: widget.runtime,
            isCurrent: () => widget.runtime.isCurrent,
            builder: _businessPage);
      }));

  Widget _businessPage(BuildContext context) {
    if (widget.agent) {
      if (widget.section == 'personal') {
        return SangongAgentPersonalPage(
            imGroupId: widget.runtime.featureContext.groupID);
      }
      if (widget.section == 'team') return const SangongAgentTeamPage();
      return SangongAgentDashboardPage(
          imGroupId: widget.runtime.featureContext.groupID);
    }
    if (!widget.runtime.canManage) {
      if (widget.runtime.groupTenant.state?.status ==
          SangongGroupTenantStatus.notFound) {
        return SangongMyConfigPage(
            groupScoped: true,
            initialGameGroupId: widget.runtime.featureContext.groupID);
      }
      return SangongOperatorUnavailablePage(
          reason: widget.runtime.manageUnavailableReason ?? '当前群暂不可进行三公运营',
          onRetry: _load,
          onViewConfig: widget.runtime.canConfigure
              ? () async {
                  await SangongMyConfigPage.open(context,
                      groupScoped: widget.runtime.requiresGroupTenantCheck,
                      initialGameGroupId:
                          widget.runtime.featureContext.groupID);
                  if (mounted) await _load();
                }
              : null);
    }
    return SangongManageHomePage(
        gameGroupId: widget.runtime.featureContext.groupID,
        tenantId: widget.runtime.http.tenantId ?? '',
        canEditConfig: widget.runtime.canConfigure,
        canManageMembers: widget.runtime.canManageMembers,
        floatVisible: widget.floatVisible,
        onFloatVisibleChanged: widget.onFloatVisibleChanged);
  }
}

void _logManageUnavailable(SangongRuntime runtime, String reason) =>
    SangongApiDebugLog.permissionDenied(runtime.featureContext, reason,
        logicalTenantId: runtime.http.tenantId ?? '',
        config: runtime.requiresGroupTenantCheck
            ? runtime.groupTenant.state?.config?.toJson()
            : runtime.config.hasCachedConfig
                ? runtime.config.config.toJson()
                : null);
