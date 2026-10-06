import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../data/group_feature_store.dart';
import '../data/live_list_sync.dart';

/// Owns list-only status calibration, including its route and app lifetime.
class GroupLiveListScope extends StatefulWidget {
  const GroupLiveListScope({
    super.key,
    required this.store,
    required this.userID,
    required this.sessionCurrent,
    required this.child,
    this.active = true,
  });

  final GroupFeatureStore store;
  final String userID;
  final bool Function() sessionCurrent;
  final Widget child;
  final bool active;

  static GroupLiveListSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiveListBinding>()?.sync;

  @override
  State<GroupLiveListScope> createState() => _GroupLiveListScopeState();
}

class _GroupLiveListScopeState extends State<GroupLiveListScope>
    with WidgetsBindingObserver {
  late GroupLiveListSync _sync;
  bool _foreground = true;
  bool _routeCurrent = true;
  int _activation = 0;

  void _create() {
    _sync = GroupLiveListSync(
      store: widget.store,
      userID: widget.userID,
      sessionCurrent: () => mounted && widget.sessionCurrent(),
    );
  }

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _create();
  }

  void _activateAfterLayout() {
    final activation = ++_activation;
    // Changing a route/tab can happen during build. Start reads after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && activation == _activation) {
        _sync.setActive(widget.active && _foreground && _routeCurrent);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.of(context)?.isCurrent != false;
    _activateAfterLayout();
  }

  @override
  void didUpdateWidget(GroupLiveListScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store) ||
        oldWidget.userID != widget.userID) {
      _sync.dispose();
      _create();
    }
    if (!widget.active) _sync.setActive(false);
    _activateAfterLayout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync.setActive(widget.active && _foreground && _routeCurrent);
  }

  @override
  void dispose() {
    ++_activation;
    WidgetsBinding.instance.removeObserver(this);
    _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.store.active
      ? _LiveListBinding(sync: _sync, child: widget.child)
      : widget.child;
}

class _LiveListBinding extends InheritedWidget {
  const _LiveListBinding({required this.sync, required super.child});
  final GroupLiveListSync sync;

  @override
  bool updateShouldNotify(_LiveListBinding oldWidget) =>
      !identical(oldWidget.sync, sync);
}

/// Only avatars actually inside the viewport participate in list calibration.
class GroupLiveListItem extends StatefulWidget {
  const GroupLiveListItem({
    super.key,
    required this.groupID,
    required this.child,
  });
  final String groupID;
  final Widget child;

  @override
  State<GroupLiveListItem> createState() => _GroupLiveListItemState();
}

class _GroupLiveListItemState extends State<GroupLiveListItem> {
  final _source = Object();
  GroupLiveListSync? _sync;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = GroupLiveListScope.maybeOf(context);
    if (!identical(next, _sync)) {
      _sync?.setVisible(_source, widget.groupID, false);
      _sync = next;
      if (_visible) _sync?.setVisible(_source, widget.groupID, true);
    }
  }

  @override
  void didUpdateWidget(GroupLiveListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupID != widget.groupID) {
      _sync?.setVisible(_source, oldWidget.groupID, false);
      if (_visible) _sync?.setVisible(_source, widget.groupID, true);
    }
  }

  @override
  void dispose() {
    _sync?.setVisible(_source, widget.groupID, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _sync == null
      ? widget.child
      : VisibilityDetector(
          key: ObjectKey(_source),
          onVisibilityChanged: (info) {
            if (!mounted) return;
            _visible = info.visibleFraction > 0;
            _sync?.setVisible(_source, widget.groupID, _visible);
          },
          child: widget.child,
        );
}
