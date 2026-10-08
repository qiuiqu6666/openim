import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;
import '../../../../core/controller/im_controller.dart';
import '../../data/group_feature_runtime.dart';
import '../sangong_scope.dart';
import '../api/profile/sangong_profile_groups_api.dart';
import '../api/diagnostics/sangong_api_debug_log.dart';
import '../support/sangong_ui.dart' show DioErrorMessage;
import 'sangong_profile_entry_scope.dart';
import 'sangong_profile_panel.dart';
import 'sangong_profile_ledger.dart';
import 'sangong_profile_admin_tokens.dart';
import 'sangong_profile_ledger_floating_entry.dart';
import 'sangong_profile_ledger_unavailable.dart';
import '../widgets/authorization/privilege_route_guard.dart';

/// Account privilege exposes services; verified group permission protects data.
class SangongProfileSurface extends StatefulWidget {
  const SangongProfileSurface(
      {super.key,
      required this.userID,
      required this.child,
      this.groupID,
      this.store,
      this.loadGroups});
  final String userID;
  final String? groupID;
  final Widget child;
  final GroupFeatureStore? store;
  final Future<List<GroupInfo>> Function()? loadGroups;
  @override
  State<SangongProfileSurface> createState() => _SangongProfileSurfaceState();
}

class _SangongProfileSurfaceState extends State<SangongProfileSurface> {
  GroupFeatureStore? _store;
  SangongRuntime? _runtime;
  List<GroupInfo> _groups = [];
  String? _selected;
  String? _error;
  String _owner = '';
  int _generation = 0;
  bool _loading = false;
  bool _discovering = false;
  bool _lastPrivileged = false;
  bool _ledgerOpen = false;
  final _ledgerScopeChanges = ValueNotifier<int>(0);

  bool get _privileged {
    final store = _store;
    return store != null &&
        store.active &&
        _owner == OpenIM.iMManager.userID &&
        store.accountPrivilege
            .allows(userID: _owner, baseUrl: store.api.baseUrl);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_discover());
  }

  @override
  void didUpdateWidget(SangongProfileSurface old) {
    super.didUpdateWidget(old);
    if (old.userID != widget.userID ||
        old.groupID != widget.groupID ||
        !identical(old.store, widget.store)) {
      _clear();
      unawaited(_discover());
    }
  }

  void _releaseRuntime() {
    final runtime = _runtime;
    _runtime = null;
    runtime?.dispose();
  }

  void _clear() {
    _generation++;
    _store?.removeListener(_authorizationChanged);
    _store?.accountPrivilege.removeListener(_authorizationChanged);
    _releaseRuntime();
    _store = null;
    _owner = '';
    _groups = [];
    _selected = null;
    _error = null;
    _loading = false;
    _discovering = false;
    _lastPrivileged = false;
    _ledgerScopeChanges.value++;
  }

  @override
  void dispose() {
    _clear();
    _ledgerScopeChanges.dispose();
    super.dispose();
  }

  bool _current(int generation, GroupFeatureStore store, String owner) =>
      mounted &&
      generation == _generation &&
      identical(store, _store) &&
      owner == _owner &&
      owner == OpenIM.iMManager.userID &&
      store.active;

  Future<void> _discover({bool refreshPrivilege = true}) async {
    if (_discovering) return;
    if (widget.store == null && !Get.isRegistered<IMController>()) return;
    final owner = OpenIM.iMManager.userID;
    if (owner.isEmpty || widget.userID.isEmpty || widget.userID == owner) {
      return;
    }
    final store = widget.store ??
        GroupFeatureRuntime.forAccount(Get.find<IMController>());
    if (!identical(_store, store)) {
      _store?.removeListener(_authorizationChanged);
      _store?.accountPrivilege.removeListener(_authorizationChanged);
      store.addListener(_authorizationChanged);
      store.accountPrivilege.addListener(_authorizationChanged);
    }
    _store = store;
    _owner = owner;
    final generation = ++_generation;
    final previousSelection = _selected;
    _lastPrivileged = _privileged;
    _discovering = true;
    _releaseRuntime();
    setState(() {
      _loading = true;
      _error = null;
      _groups = [];
      _selected = null;
    });
    try {
      // The grant notification is consumed here, not by a second discovery.
      final allowed = refreshPrivilege
          ? await store.accountPrivilege.refresh()
          : _privileged;
      if (!_current(generation, store, owner) || !allowed || !_privileged) {
        return;
      }
      _lastPrivileged = true;
      final groups = widget.loadGroups != null
          ? await widget.loadGroups!()
          : await SangongProfileGroupsApi(store.api).load();
      if (!_current(generation, store, owner) || !_privileged) return;
      final candidates = <String, GroupInfo>{};
      for (final group in groups) {
        if (group.groupID.isEmpty) {
          continue;
        }
        candidates[group.groupID] = group;
        store.seed(group);
      }
      if (!_current(generation, store, owner) || !_privileged) return;
      // Neither old SDK summaries nor private capabilities hide the services.
      _groups = candidates.values.toList();
      _discovering = false;
      final selected = candidates.containsKey(previousSelection)
          ? previousSelection
          : _groups.length == 1
              ? _groups.single.groupID
              : null;
      if (selected != null) {
        await _select(selected, refreshPrivilege: false);
      } else {
        setState(() {
          _loading = false;
          if (_groups.isEmpty) {
            _error = '暂无已配置或授权的游戏群，请先配置游戏群或联系配置者授权';
          }
        });
      }
    } catch (failure) {
      if (_current(generation, store, owner) && _privileged) {
        setState(() {
          _loading = false;
          _error = DioErrorMessage.forApp(failure);
        });
      }
    } finally {
      if (_current(generation, store, owner)) {
        _discovering = false;
        if (!_privileged) setState(() => _loading = false);
      } else if (mounted &&
          identical(store, _store) &&
          owner == _owner &&
          (!store.active || owner != OpenIM.iMManager.userID)) {
        _authorizationChanged();
      }
    }
  }

  void _authorizationChanged() {
    final store = _store;
    if (!mounted || store == null) return;
    final privileged = _privileged;
    final restored = privileged && !_lastPrivileged;
    _lastPrivileged = privileged;
    if (!privileged) {
      _generation++;
      _releaseRuntime();
      _groups = [];
      _selected = null;
      _error = null;
      _loading = false;
      _discovering = false;
      setState(() {});
      return;
    }
    if (restored && !_discovering && !_loading) {
      unawaited(_discover(refreshPrivilege: false));
      return;
    }
    final runtime = _runtime;
    if (runtime != null && !_loading) {
      runtime.updateContext(runtime.featureContext.readCurrentContext());
      if (!runtime.canManage) {
        _error = '当前群的三公业务权限已变化，请重试';
      }
    }
    setState(() {});
  }

  Future<void> _select(String id, {bool refreshPrivilege = true}) async {
    final store = _store;
    if (store == null || !_privileged) return;
    final group = _groups.where((group) => group.groupID == id).firstOrNull;
    if (group == null) return;
    final owner = _owner;
    final generation = ++_generation;
    _discovering = false;
    _releaseRuntime();
    setState(() {
      _selected = id;
      _loading = true;
      _error = null;
    });
    try {
      final allowed = refreshPrivilege
          ? await store.accountPrivilege.refresh()
          : _privileged;
      if (!_current(generation, store, owner) || !allowed || !_privileged) {
        return;
      }
      final entry = store.context(
          id: id,
          name: group.groupName ?? id,
          userID: owner,
          admin: false,
          current: () =>
              mounted &&
              identical(_store, store) &&
              _owner == owner &&
              OpenIM.iMManager.userID == owner &&
              _selected == id);
      final current = await SangongApiDebugLog.trace(
          () => entry.refreshCapabilities(force: true));
      if (!_current(generation, store, owner) || !_privileged) return;
      final capability = current.capabilities.sangong;
      if (!capability.canConfigure && !capability.canManage) {
        SangongApiDebugLog.permissionDenied(current, '没有当前群的三公配置或运营权限');
        throw StateError('没有当前群的三公配置或运营权限');
      }
      final runtime = SangongRuntime(current);
      _runtime = runtime;
      await runtime.ensureManageBinding();
      if (!_current(generation, store, owner) ||
          !_privileged ||
          !identical(_runtime, runtime)) {
        return;
      }
      runtime.updateContext(runtime.featureContext.readCurrentContext());
      if (!runtime.canManage) {
        throw StateError('当前群尚未确认三公运营绑定，请在群聊三公管理中完成配置后重试');
      }
    } catch (failure) {
      if (_current(generation, store, owner) && _privileged) {
        setState(() => _error = DioErrorMessage.forApp(failure));
      }
    } finally {
      if (_current(generation, store, owner)) {
        setState(() => _loading = false);
      } else if (mounted &&
          identical(store, _store) &&
          owner == _owner &&
          (!store.active || owner != OpenIM.iMManager.userID)) {
        _authorizationChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_privileged || widget.userID == _owner) return widget.child;
    final runtime = _runtime;
    final contents = Builder(builder: (scoped) {
      final canManage =
          runtime?.canManage == true && !_loading && _error == null;
      final selectionStore = _store!;
      final selectionOwner = _owner;
      final selectionTarget = widget.userID;
      final selectionGroup = _groups.length > 1 ? _groups.first : null;
      final selectionContext = selectionGroup == null
          ? null
          : selectionStore.context(
              id: selectionGroup.groupID,
              name: selectionGroup.groupName ?? selectionGroup.groupID,
              userID: selectionOwner,
              admin: false,
              current: () =>
                  mounted &&
                  identical(_store, selectionStore) &&
                  _owner == selectionOwner &&
                  OpenIM.iMManager.userID == selectionOwner &&
                  widget.userID == selectionTarget &&
                  _privileged);
      return SangongProfileEntryScope(
          userID: widget.userID,
          groups: List.unmodifiable(_groups),
          selectedGroupID: _selected,
          loading: _loading,
          error: _error,
          selectionContext: selectionContext,
          selectionChanges: selectionStore,
          onRetry: () => unawaited(_discover()),
          onSelectGroup: (id) => unawaited(_select(id)),
          onLedger: () {
            if (!scoped.mounted ||
                !identical(_store, selectionStore) ||
                _owner != selectionOwner ||
                widget.userID != selectionTarget) {
              return;
            }
            unawaited(_openLedgerEntry(scoped));
          },
          child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Stack(children: [
                widget.child,
                SangongProfileLedgerFloatingEntry(
                    key: ValueKey('profile-ledger:$_owner'),
                    preferenceKey: '$_owner:${_store!.api.baseUrl}',
                    onOpenLedger:
                        SangongProfileEntryScope.maybeOf(context)?.onLedger),
              ]);
            }
            final dark = Theme.of(context).brightness == Brightness.dark;
            final sidePanel =
                SangongProfileEntryCard(userID: widget.userID, embedded: true);
            final ledger = canManage
                ? SangongProfileLedger(
                    key: ValueKey('${runtime!.preferenceKey}:${widget.userID}'),
                    userID: widget.userID)
                : const SizedBox.shrink();
            final sideBody = constraints.maxHeight >= 600
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [sidePanel, Expanded(child: ledger)])
                : SingleChildScrollView(
                    child: Column(children: [
                    sidePanel,
                    if (canManage) SizedBox(height: 600, child: ledger)
                  ]));
            return Row(children: [
              Expanded(child: widget.child),
              SizedBox(
                  width: SangongProfileAdminTokens.sideWidth,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: AppTokens.surface(dark: dark),
                          border: Border(
                              left: BorderSide(
                                  color: AppTokens.border(dark: dark)
                                      .withValues(alpha: .9)))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                                height:
                                    SangongProfileAdminTokens.sideHeaderHeight,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppTokens.s5),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                    border: Border(
                                        bottom: BorderSide(
                                            color: AppTokens.border(dark: dark)
                                                .withValues(alpha: .85)))),
                                child: Text('游戏管理',
                                    style: TextStyle(
                                        fontSize: 16,
                                        height: 1.25,
                                        fontWeight: FontWeight.w600,
                                        color: AppTokens.textPrimary(
                                            dark: dark)))),
                            Expanded(child: sideBody),
                          ])))
            ]);
          }));
    });
    return runtime == null
        ? contents
        : SangongScope(runtime: runtime, child: contents);
  }

  Future<void> _openLedgerEntry(BuildContext context) async {
    if (_ledgerOpen || !_privileged) return;
    _ledgerOpen = true;
    final store = _store!;
    final owner = _owner;
    final target = widget.userID;
    bool current() =>
        mounted &&
        identical(store, _store) &&
        owner == _owner &&
        owner == OpenIM.iMManager.userID &&
        target == widget.userID &&
        store.active;
    try {
      final runtime = _runtime;
      if (runtime?.canManage == true && !_loading && _error == null) {
        await _openLedger(context, runtime!);
        return;
      }
      final choice = await showModalBottomSheet<SangongProfileLedgerChoice>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: const Color(0xFF000000).withValues(alpha: .45),
          builder: (context) => SangongPrivilegeRouteGuard.account(
              privilege: store.accountPrivilege,
              userID: owner,
              baseUrl: store.api.baseUrl,
              sessionCurrent: current,
              scopeChanges: Listenable.merge([store, _ledgerScopeChanges]),
              builder: (context) => Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom),
                  child: SizedBox(
                      height: MediaQuery.sizeOf(context).height * .82,
                      child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                          child: SangongProfileLedgerUnavailable(
                              groups: List.unmodifiable(_groups),
                              selectedGroupID: _selected,
                              loading: _loading,
                              error: _error))))));
      if (choice == null || !current() || !_privileged) return;
      if (choice.groupID == null) {
        unawaited(_discover());
      } else {
        unawaited(_select(choice.groupID!));
      }
    } finally {
      _ledgerOpen = false;
    }
  }

  Future<void> _openLedger(BuildContext context, SangongRuntime runtime) {
    final target = widget.userID;
    return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0xFF000000).withValues(alpha: .45),
        builder: (context) => SangongPrivilegeRouteGuard(
            featureContext: runtime.featureContext,
            scopeChanges: runtime,
            isCurrent: () =>
                mounted &&
                identical(_runtime, runtime) &&
                runtime.isCurrent &&
                target == widget.userID,
            builder: (context) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * .82,
                    child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: SangongScope(
                            runtime: runtime,
                            child: SangongProfileLedger(userID: target)))))));
  }
}
