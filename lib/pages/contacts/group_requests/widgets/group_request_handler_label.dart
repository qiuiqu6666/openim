import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';
import '../../request_history/presentation/request_history_labels.dart';
import '../../request_history/presentation/request_history_style.dart';

class GroupRequestHandlerLabel extends StatelessWidget {
  const GroupRequestHandlerLabel({
    super.key,
    required this.nickname,
    this.textAlign = TextAlign.start,
    this.compact = false,
    this.onTap,
  });

  final String? nickname;
  final TextAlign textAlign;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = nickname?.trim();
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    if (onTap != null) {
      return Padding(
        padding: EdgeInsets.only(top: compact ? AppTokens.s2 : 4.h),
        child: InkWell(
          onTap: onTap,
          child: Text(
              compact
                  ? RequestHistoryLabels.handler(name)
                  : sprintf(StrRes.groupRequestHandledBy, [name]),
              style: (compact
                      ? RequestHistoryStyle.metadata(context)
                      : Styles.ts_8E9AB0_14sp)
                  .copyWith(color: AppTokens.accent),
              textAlign: textAlign,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: compact ? AppTokens.s2 : 4.h),
      child: Text(
        compact
            ? RequestHistoryLabels.handler(name)
            : sprintf(StrRes.groupRequestHandledBy, [name]),
        style: compact
            ? RequestHistoryStyle.metadata(context)
            : Styles.ts_8E9AB0_14sp,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
