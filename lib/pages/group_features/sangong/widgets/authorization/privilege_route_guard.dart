import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../models/group_feature_context.dart';
import '../../../../../services/account_privilege/account_privilege_store.dart';

/// Owns only the explicit game route containing this widget. Embedded game
/// content in an ordinary chat or profile uses its content guard instead.
class SangongPrivilegeRouteGuard extends StatefulWidget {
  const SangongPrivilegeRouteGuard({
    super.key,
    required GroupFeatureContext this.featureContext,
    required this.builder,
    this.refreshOnEntry = true,
    this.requireCapabilitiesCurrent = true,
    this.scopeChanges,
    this.isCurrent,
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
        requireCapabilitiesCurrent = false;

  final GroupFeatureContext? featureContext;
  final AccountPrivilegeAccess? accountPrivilege;
  final String? userID, baseUrl;
  final bool Function()? sessionCurrent;
  final WidgetBuilder builder;
  final bool refreshOnEntry;

  /// The public module entry may show permission loading/errors. Private
  /// business pages keep the captured capability fence enabled.
  final bool requireCapabilitiesCurrent;
  final Listenable? scopeChanges;
  final bool Function()? isCurrent;

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

  bool get _allowed => _privilege.allows(userID: _userID, baseUrl: _baseUrl);
  bool get _current =>
      (_entry?.sessionCurrent() ?? widget.sessionCurrent!()) &&
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
    } else if (_allowed && _current) {
      _ready = true;
      _authorizedRevision = _privilege.revision;
    } else {
      _close();
    }
  }

  Future<void> _authorize() async {
    bool confirmed;
    try {
      confirmed = await _privilege.refresh();
    } catch (_) {
      confirmed = false;
    }
    if (!mounted || _closing) return;
    if (!confirmed || !_allowed || !_current) {
      _close();
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
    final allowed = _allowed;
    if (!_current ||
        (_sawAllowed && !allowed) ||
        (_ready &&
            (!allowed ||
                !_current ||
                _authorizedRevision != _privilege.revision))) {
      _close();
      return;
    }
    _sawAllowed = _sawAllowed || allowed;
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
    if (_ready &&
        (!_allowed ||
            !_current ||
            _authorizedRevision != _privilege.revision)) {
      _close(notify: false);
    }
    if (_closing) return const SizedBox.shrink();
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return widget.builder(context);
  }
}
