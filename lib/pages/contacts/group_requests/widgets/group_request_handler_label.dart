import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

class GroupRequestHandlerLabel extends StatelessWidget {
  const GroupRequestHandlerLabel({
    super.key,
    required this.nickname,
    this.textAlign = TextAlign.start,
  });

  final String? nickname;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final name = nickname?.trim();
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: Text(
        sprintf(StrRes.groupRequestHandledBy, [name]),
        style: Styles.ts_8E9AB0_14sp,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
