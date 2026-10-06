import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatTimelineView extends StatelessWidget {
  const ChatTimelineView({
    super.key,
    required this.timeStr,
    this.margin,
    this.onTap,
    this.semanticLabel,
  });
  final String timeStr;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tip = Container(
      padding: EdgeInsets.symmetric(vertical: 2.h, horizontal: 6.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(timeStr,
          style: Styles.ts_8E9AB0_12sp
              .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTap == null
          ? tip
          : TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(
                    kMinInteractiveDimension, kMinInteractiveDimension),
                padding: EdgeInsets.zero,
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: Semantics(
                label:
                    semanticLabel == null ? null : '$timeStr, $semanticLabel',
                excludeSemantics: semanticLabel != null,
                child: tip,
              ),
            ),
    );
  }
}
