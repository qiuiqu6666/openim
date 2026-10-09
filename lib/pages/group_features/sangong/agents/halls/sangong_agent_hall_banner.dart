import 'package:flutter/material.dart';

/// The hall is fixed by this agent group and is displayed for orientation.
class SangongAgentHallBanner extends StatelessWidget {
  const SangongAgentHallBanner({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
            dense: true,
            leading: const Icon(Icons.storefront_outlined),
            title: Text('所属厅：$name',
                maxLines: 2, overflow: TextOverflow.ellipsis)),
      );
}
