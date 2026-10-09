import 'package:flutter/material.dart';

/// Only the main agent screen offers switching. Pushed detail routes retain
/// their own immutable hall and show the same label without a switch action.
class SangongAgentHallSelection extends InheritedWidget {
  const SangongAgentHallSelection(
      {super.key, required this.onChoose, required super.child});
  final VoidCallback onChoose;
  static SangongAgentHallSelection? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SangongAgentHallSelection>();
  @override
  bool updateShouldNotify(SangongAgentHallSelection oldWidget) =>
      oldWidget.onChoose != onChoose;
}

class SangongAgentHallBanner extends StatelessWidget {
  const SangongAgentHallBanner({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final choose = SangongAgentHallSelection.of(context)?.onChoose;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.storefront_outlined),
        title: Text('当前厅：$name', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: choose == null
            ? null
            : TextButton(onPressed: choose, child: const Text('切换厅')),
      ),
    );
  }
}
