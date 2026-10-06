import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'chat_composer_palette.dart';

class ChatDisableInputBox extends StatelessWidget {
  const ChatDisableInputBox({super.key, this.type = 0, this.message});

  final int type;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return type == 0
        ? Container(
            key: const ValueKey('chat-disabled-input-bar'),
            constraints: BoxConstraints(minHeight: AppTokens.listItemHeight.h),
            padding: EdgeInsets.symmetric(
              horizontal: ChatComposerTokens.horizontalPadding.w,
              vertical: AppTokens.s3.h,
            ),
            color: chatComposerSurface(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ImageRes.warn.toImage
                  ..width = 14.w
                  ..height = 14.h,
                6.horizontalSpace,
                Flexible(
                  child: Text(
                    message ?? StrRes.notSendMessageNotInGroup,
                    textAlign: TextAlign.center,
                    style: Styles.ts_8E9AB0_14sp,
                  ),
                ),
              ],
            ),
          )
        : Container();
  }
}
