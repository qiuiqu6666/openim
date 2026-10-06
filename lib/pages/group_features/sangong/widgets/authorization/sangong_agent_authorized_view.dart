import 'package:flutter/material.dart';
import '../../sangong_scope.dart';
import '../app_back_button.dart';

/// Keeps private agent content out of the tree as soon as its captured scope
/// or the required capability changes, including for directly opened pages.
class SangongAgentAuthorizedView extends StatefulWidget {
  const SangongAgentAuthorizedView({
    super.key,
    required this.runtime,
    required this.session,
    required this.child,
    this.requireHistory = false,
  });

  final SangongRuntime runtime;
  final AgentSessionSnapshot session;
  final Widget child;
  final bool requireHistory;

  @override
  State<SangongAgentAuthorizedView> createState() =>
      _SangongAgentAuthorizedViewState();
}

class _SangongAgentAuthorizedViewState
    extends State<SangongAgentAuthorizedView> {
  bool get _authorized =>
      widget.session.isCurrent &&
      widget.runtime.canOpenAgent &&
      (!widget.requireHistory || widget.runtime.canViewRebateHistory);

  @override
  void initState() {
    super.initState();
    _listen(widget.runtime);
  }

  void _listen(SangongRuntime runtime) {
    runtime.addListener(_changed);
    runtime.http.tenantIdListenable.addListener(_changed);
  }

  void _unlisten(SangongRuntime runtime) {
    runtime.removeListener(_changed);
    runtime.http.tenantIdListenable.removeListener(_changed);
  }

  @override
  void didUpdateWidget(covariant SangongAgentAuthorizedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) {
      _unlisten(oldWidget.runtime);
      _listen(widget.runtime);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _unlisten(widget.runtime);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _authorized
      ? widget.child
      : Scaffold(
          appBar: AppBar(
            leading: const AppBackButton(),
            title: const Text('三公代理'),
          ),
          body: const Center(child: Text('当前游戏权限已变化，请重新进入')),
        );
}
