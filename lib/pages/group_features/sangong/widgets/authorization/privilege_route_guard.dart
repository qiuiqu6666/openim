import 'package:openim_common/localization.dart';
import '../../services/authorization/sangong_access_policy.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../models/group_feature_context.dart';
import '../../../../../services/account_privilege/account_privilege_store.dart';
import '../../support/settings_exports.dart';

/// Owns only the explicit game route containing this widget. Embedded game
/// content in an ordinary chat or profile uses its content guard instead.
class SangongPrivilegeRouteGuard extends StatefulWidget {
  const SangongPrivilegeRouteGuard({
    super.key,
    required GroupFeatureContext this.featureContext,
    required this.builder,
    this.allowAssignedAgent = false,
    this.refreshOnEntry = true,
    this.requireCapabilitiesCurrent = true,
    this.scopeChanges,
    this.isCurrent,
    this.canRevalidate,
    this.revalidate,
    this.preserveForm = false,
  })  : accountPrivilege = null,
        userID = null,
        baseUrl = null,
        sessionCurrent = null;

  /// Public loading/error routes can open before a real group is available.
  /// This grant never authorizes private group data or operations.
  const SangongPrivilegeRouteGuard.account({
    super.key,
    required AccountPrivilegeAccess privilege,
    required String this.userID,
    required String this.baseUrl,
    required bool Function() this.sessionCurrent,
    required this.builder,
    this.refreshOnEntry = true,
    this.scopeChanges,
    this.isCurrent,
  })  : featureContext = null,
        accountPrivilege = privilege,
        requireCapabilitiesCurrent = false,
        allowAssignedAgent = false,
        canRevalidate = null,
        revalidate = null,
        preserveForm = false;

  final GroupFeatureContext? featureContext;
  final AccountPrivilegeAccess? accountPrivilege;
  final String? userID, baseUrl;
  final bool Function()? sessionCurrent;
  final WidgetBuilder builder;
  final bool refreshOnEntry, allowAssignedAgent;

  /// The public module entry may show permission loading/errors. Private
  /// business pages keep the captured capability fence enabled.
  final bool requireCapabilitiesCurrent;
  final Listenable? scopeChanges;
  final bool Function()? isCurrent;
  final bool Function()? canRevalidate;
  final Future<bool> Function(bool Function() active)? revalidate;

  /// Only forms whose revalidation verifies the original business target may
  /// retain their draft. Other private pages still discard stale content.
  final bool preserveForm;

  @override
  State<SangongPrivilegeRouteGuard> createState() =>
      _SangongPrivilegeRouteGuardState();
}

class _SangongPrivilegeRouteGuardState
    extends State<SangongPrivilegeRouteGuard> {
  late final _entry = widget.featureContext;
  late final _privilege = _entry?.privilege ?? widget.accountPrivilege!;
  late final _userID = _entry?.currentUserID ?? widget.userID!;
  late final _baseUrl = _entry?.api.baseUrl ?? widget.baseUrl!;
  bool _ready = false;
  bool _closing = false;
  bool _sawAllowed = false;
  int? _authorizedRevision;
  bool _revalidating = false;
  bool _revalidationFailed = false;
  int _contentGeneration = 0;
  bool _formMounted = false;

  bool get _agentAllowed =>
      widget.allowAssignedAgent &&
      _entry != null &&
      (sangongAssignedAgentAccess(_entry.readCurrentContext()) ||
          (widget.canRevalidate?.call() ?? false));
  bool get _allowed =>
      _privilege.allows(userID: _userID, baseUrl: _baseUrl) || _agentAllowed;
  bool get _sessionCurrent =>
      _entry?.sessionCurrent() ?? widget.sessionCurrent!();
  bool get _current =>
      _sessionCurrent &&
      (!widget.requireCapabilitiesCurrent || _entry!.capabilitiesCurrent()) &&
      (widget.isCurrent?.call() ?? true);

  @override
  void initState() {
    super.initState();
    _sawAllowed = _allowed;
    _privilege.addListener(_changed);
    widget.scopeChanges?.addListener(_changed);
    if (widget.refreshOnEntry) {
      unawaited(_authorize());
    } else if (_allowed) {
      _authorizedRevision = _privilege.revision;
      if (_current) {
        _ready = true;
      } else {
        _recoverOrClose(notify: false);
      }
    } else {
      _close();
    }
  }

  Future<void> _authorize() async {
    bool confirmed;
    try {
      confirmed = _agentAllowed || await _privilege.refresh();
    } catch (_) {
      confirmed = false;
    }
    if (!mounted || _closing) return;
    if (!confirmed || !_allowed) {
      _close();
      return;
    }
    _authorizedRevision = _privilege.revision;
    if (!_current) {
      _recoverOrClose();
      return;
    }
    setState(() {
      _ready = true;
      _sawAllowed = true;
      _authorizedRevision = _privilege.revision;
    });
  }

  void _changed() {
    if (!mounted || _closing) return;
    // Identity can change before the first authorization request completes.
    // Do not keep an orphan loading route waiting for that old request.
    if (!_sessionCurrent) {
      _close();
      return;
    }
    final allowed = _allowed;
    if ((_sawAllowed && !allowed) ||
        (_authorizedRevision != null &&
            (!allowed || _authorizedRevision != _privilege.revision))) {
      _close();
      return;
    }
    _sawAllowed = _sawAllowed || allowed;
    // Group events can arrive before the entry account check finishes.
    if (_authorizedRevision != null && !_current) _recoverOrClose();
  }

  void _recoverOrClose({bool notify = true}) {
    if (widget.revalidate == null || !(widget.canRevalidate?.call() ?? false)) {
      _close(notify: notify);
      return;
    }
    if (_revalidating || _revalidationFailed) return;
    _ready = false;
    _revalidating = true;
    if (notify &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      setState(() {});
    }
    // A runtime can invalidate this guard while its route is being built.
    // Revalidation only reads, and is fenced when this route is removed.
    scheduleMicrotask(() async {
      bool active() => mounted && !_closing;
      if (!active()) return;
      try {
        final allowed = await widget.revalidate!(active);
        if (!active()) return;
        if (!allowed || !_allowed) {
          _close();
          return;
        }
        // A newer invalidation can arrive between the read and this callback.
        // Keep the route recoverable instead of treating that race as denial.
        if (!_current) throw StateError('群权限仍在更新');
        setState(() {
          if (!widget.preserveForm) _contentGeneration++;
          _ready = true;
          _sawAllowed = true;
          _authorizedRevision = _privilege.revision;
        });
      } catch (_) {
        if (!active()) return;
        if (!_allowed || !(widget.canRevalidate?.call() ?? false)) {
          _close();
          return;
        }
        setState(() => _revalidationFailed = true);
      } finally {
        _revalidating = false;
      }
    });
  }

  void _close({bool notify = true}) {
    if (_closing) return;
    _closing = true;
    _ready = false;
    // A profile can invalidate its scope from didUpdateWidget/dispose while
    // another route is building. Removal below is already deferred safely.
    if (mounted &&
        notify &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      setState(() {});
    }
    // Covered routes must remove themselves, never pop an unrelated top route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      if (navigator.mounted && route != null && route.isActive) {
        navigator.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(SangongPrivilegeRouteGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scopeChanges, widget.scopeChanges)) {
      oldWidget.scopeChanges?.removeListener(_changed);
      widget.scopeChanges?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _privilege.removeListener(_changed);
    widget.scopeChanges?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready && (!_allowed || _authorizedRevision != _privilege.revision)) {
      _close(notify: false);
    }
    if (_ready && !_current) _recoverOrClose(notify: false);
    if (_closing) return const SizedBox.shrink();
    if (widget.preserveForm && (_ready || _formMounted)) {
      _formMounted = true;
      final blocked = !_ready;
      return Stack(
        children: [
          ExcludeFocus(
            excluding: blocked,
            child: AbsorbPointer(
              absorbing: blocked,
              child: ExcludeSemantics(
                excluding: blocked,
                child: Builder(builder: widget.builder),
              ),
            ),
          ),
          if (blocked)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: _revalidationFailed
                    ? TextButton(
                        onPressed: () {
                          _revalidationFailed = false;
                          _recoverOrClose();
                        },
                        child: Text(AppCopy.text('暂时无法确认当前群权限，点击重试')),
                      )
                    : LinearProgressIndicator(
                        semanticsLabel: AppCopy.text('正在确认当前群权限'),
                      ),
              ),
            ),
        ],
      );
    }
    if (_revalidationFailed) {
      return SettingsScaffold(title: '三公', children: [
        Text(AppCopy.text('暂时无法确认当前群权限，请重试'), textAlign: TextAlign.center),
        SettingsPrimaryButton(
            text: AppCopy.text('重试'),
            onPressed: () {
              _revalidationFailed = false;
              _recoverOrClose();
            }),
      ]);
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return KeyedSubtree(
      key: ValueKey(_contentGeneration),
      child: Builder(builder: widget.builder),
    );
  }
}
