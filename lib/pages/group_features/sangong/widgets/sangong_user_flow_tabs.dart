import 'package:flutter/material.dart';

/// Keeps ledger tabs reachable while the user/detail controls scroll away.
class SangongUserFlowTabs extends SliverPersistentHeaderDelegate {
  const SangongUserFlowTabs();

  static const _tabs = TabBar(tabs: [
    Tab(text: '下注流水'),
    Tab(text: '庄流水'),
    Tab(text: '上下分'),
  ]);

  @override
  double get minExtent => _tabs.preferredSize.height;
  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(color: Theme.of(context).colorScheme.surface, child: _tabs);

  @override
  bool shouldRebuild(SangongUserFlowTabs oldDelegate) => false;
}
