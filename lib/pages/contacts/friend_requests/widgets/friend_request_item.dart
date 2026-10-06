import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../source/friend_application_source.dart';

class FriendRequestItem extends StatelessWidget {
  const FriendRequestItem({
    super.key,
    required this.application,
    required this.outgoing,
    required this.onView,
  });

  final FriendApplicationInfo application;
  final bool outgoing;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final name = outgoing ? application.toNickname : application.fromNickname;
    final face = outgoing ? application.toFaceURL : application.fromFaceURL;
    final reason = application.reqMsg?.trim() ?? '';
    final source = friendApplicationSourceLabel(application.ex,
        english: Get.locale?.languageCode == 'en');
    return Container(
      constraints: BoxConstraints(minHeight: 68.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        border: BorderDirectional(
          bottom: BorderSide(color: Styles.c_F8F9FA, width: 1),
        ),
      ),
      child: Row(
        children: [
          AvatarView(url: face, text: name),
          10.horizontalSpace,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name ?? '',
                    style: Styles.ts_0C1C33_17sp,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (reason.isNotEmpty) ...[
                  4.verticalSpace,
                  Text(reason,
                      style: Styles.ts_8E9AB0_14sp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                4.verticalSpace,
                Text(source,
                    key: const ValueKey('friend_application_source'),
                    style: Styles.ts_8E9AB0_14sp),
              ],
            ),
          ),
          if (outgoing)
            ImageRes.sendRequests.toImage
              ..width = 20.w
              ..height = 20.h,
          if (application.isWaitingHandle && !outgoing)
            Button(
              text: StrRes.lookOver,
              textStyle: Styles.ts_FFFFFF_14sp,
              onTap: onView,
              height: 28.h,
              padding: EdgeInsets.symmetric(horizontal: 13.w),
            ),
          if (application.isWaitingHandle && outgoing)
            Text(StrRes.waitingForVerification, style: Styles.ts_8E9AB0_14sp),
          if (application.isRejected)
            Text(StrRes.rejected, style: Styles.ts_8E9AB0_14sp),
          if (application.isAgreed)
            Text(StrRes.approved, style: Styles.ts_8E9AB0_14sp),
        ],
      ),
    );
  }
}
