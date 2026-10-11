import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/widgets/settings_widgets.dart';

/// Reveals an action only; the owner confirms and removes the saved record.
class FavoriteSwipeDelete extends StatefulWidget {
  const FavoriteSwipeDelete({
    super.key,
    required this.id,
    required this.enabled,
    required this.onDelete,
    required this.child,
  });

  final String id;
  final bool enabled;
  final Future<void> Function() onDelete;
  final Widget child;

  @override
  State<FavoriteSwipeDelete> createState() => _FavoriteSwipeDeleteState();
}

class _FavoriteSwipeDeleteState extends State<FavoriteSwipeDelete>
    with SingleTickerProviderStateMixin {
  late final _controller = SlidableController(this);
  bool _acting = false;

  @override
  void didUpdateWidget(covariant FavoriteSwipeDelete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      // Auto-close notifies other rows, so it must run after their rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.enabled) {
          unawaited(_controller.close(duration: Duration.zero));
        }
      });
    }
  }

  Future<void> _delete() async {
    if (_acting || !widget.enabled) return;
    _acting = true;
    final delete = widget.onDelete;
    try {
      await _controller.close(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180));
      if (mounted && widget.enabled) await delete();
    } finally {
      _acting = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        child: Slidable(
          controller: _controller,
          enabled: widget.enabled,
          useTextDirection: false,
          groupTag: 'favorite-management',
          startActionPane: ActionPane(
            extentRatio: .25,
            motion: const DrawerMotion(),
            children: [
              SlidableAction(
                key: ValueKey('favorite-swipe-delete-${widget.id}'),
                autoClose: false,
                onPressed: (_) => unawaited(_delete()),
                backgroundColor: AppTokens.walletDanger,
                foregroundColor: AppTokens.onAccent,
                icon: Icons.delete_outline,
                label: settingsText(context, zh: '删除', en: 'Delete'),
              ),
            ],
          ),
          child: widget.child,
        ),
      );
}
