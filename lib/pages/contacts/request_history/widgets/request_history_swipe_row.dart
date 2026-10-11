import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:openim_common/openim_common.dart';

class RequestHistorySwipeRow extends StatelessWidget {
  const RequestHistorySwipeRow({
    super.key,
    required this.child,
    required this.onDelete,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Slidable(
        enabled: enabled,
        groupTag: 'request-history',
        endActionPane: ActionPane(
          extentRatio: .24,
          motion: const DrawerMotion(),
          children: [
            SlidableAction(
              onPressed: enabled ? (_) => onDelete() : null,
              backgroundColor: AppTokens.danger,
              foregroundColor: AppTokens.onAccent,
              label: StrRes.delete,
            ),
          ],
        ),
        child: child,
      );
}
