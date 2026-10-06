import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatComposerContextPreview extends StatelessWidget {
  const ChatComposerContextPreview({
    super.key,
    this.onClose,
    this.content,
    this.textSpan,
  }) : assert(content != null || textSpan != null,
            'Either content or textSpan must be provided.');
  final VoidCallback? onClose;
  final String? content;
  final InlineSpan? textSpan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      color: Styles.c_F0F2F6,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onClose,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 1.h, horizontal: 4.w),
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  children: [
                    if (content != null)
                      Expanded(
                          child: Text(
                        content!,
                        style: Styles.ts_8E9AB0_14sp,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      )),
                    if (textSpan != null)
                      Expanded(
                        child: RichText(
                          text: textSpan!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              ImageRes.delQuote.toImage
                ..width = 14.w
                ..height = 14.h,
            ],
          ),
        ),
      ),
    );
  }
}
