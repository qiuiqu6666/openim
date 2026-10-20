import 'package:flutter/material.dart';
import 'package:openim_common/localization.dart';

/// Keeps ledger tabs reachable while the user/detail controls scroll away.
class SangongUserFlowTabs extends SliverPersistentHeaderDelegate {
  const SangongUserFlowTabs();

  static TabBar get _tabs => TabBar(tabs: [
        const Tab(text: '下注流水'),
        Tab(text: AppCopy.text('庄流水')),
        const Tab(text: '上下分'),
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
