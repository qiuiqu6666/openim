import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// Only the unresolved section waits; the known group header stays visible.
class GroupSetupLoading extends StatelessWidget {
  const GroupSetupLoading({
    super.key,
    required this.failed,
    required this.onRetry,
  });

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!failed) const CircularProgressIndicator.adaptive(),
          SizedBox(height: 12.h),
          Text(
            failed ? AppCopy.text('群资料加载失败') : AppCopy.text('正在加载群资料'),
            style: Styles.ts_8E9AB0_12sp,
          ),
          if (failed)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('chatHistoryRetry'.tr),
            ),
        ]),
      );
}
