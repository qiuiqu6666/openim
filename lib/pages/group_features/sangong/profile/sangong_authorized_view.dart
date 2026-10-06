import 'package:flutter/material.dart';
import '../sangong_scope.dart';

/// Covered routes must also remove cached private content when access changes.
class SangongAuthorizedView extends StatelessWidget {
  const SangongAuthorizedView(
      {super.key, required this.runtime, required this.child, this.isCurrent});
  final SangongRuntime runtime;
  final Widget child;
  final bool Function()? isCurrent;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: runtime,
      builder: (_, __) => runtime.canManage && (isCurrent?.call() ?? true)
          ? child
          : const Center(child: Text('当前游戏权限已变化，请重新进入')));
}
