import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatCallItemView extends StatelessWidget {
  const ChatCallItemView({
    super.key,
    required this.type,
    required this.content,
  });

  final String content;
  final String type;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 164.w,
        child: Row(
          children: [
            Container(
              width: 28.w,
              height: 28.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Styles.c_0089FF
                    .withValues(alpha: Styles.isDark ? .20 : .10),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                  type == 'audio' ? Icons.call_rounded : Icons.videocam_rounded,
                  color: Styles.c_0089FF,
                  size: 19.w),
            ),
            8.horizontalSpace,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type == 'audio' ? StrRes.callVoice : StrRes.callVideo,
                      style: Styles.ts_0C1C33_17sp
                          .copyWith(fontSize: 14.sp, height: 1.3, fontWeight: FontWeight.w500)),
                  2.verticalSpace,
                  Text(content,
                      style: Styles.ts_8E9AB0_13sp
                          .copyWith(fontSize: 11.sp, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Shared icon treatment for structured chat messages.
class ChatAttachmentIcon extends StatelessWidget {
  const ChatAttachmentIcon({super.key, required this.child, this.size});
  final Widget child;
  final double? size;

  @override
  Widget build(BuildContext context) => Container(
        width: size ?? 38.w,
        height: size ?? 38.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Styles.c_0089FF.withValues(alpha: Styles.isDark ? 0.18 : 0.09),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: child,
      );
}
