import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

class NewMessageIndicator extends StatelessWidget {
  const NewMessageIndicator({
    Key? key,
    this.newMessageCount = 0,
    this.onTap,
  }) : super(key: key);
  final int newMessageCount;
  final Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final label = newMessageCount > 0
        ? sprintf(StrRes.nMessage, [newMessageCount])
        : StrRes.backToBottom;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(ChatScrollHintTokens.radius.r),
      bottomLeft: Radius.circular(ChatScrollHintTokens.radius.r),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      hint: newMessageCount > 0 ? StrRes.backToBottom : null,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: ChatScrollHintTokens.minHeight.h),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      offset: Offset(0, ChatScrollHintTokens.shadowOffset.h),
                      blurRadius: ChatScrollHintTokens.shadowBlur.r,
                      color: ChatScrollHintTokens.shadow,
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: radius,
                    excludeFromSemantics: true,
                    onTap: onTap,
                    child: Ink(
                      padding: EdgeInsets.symmetric(
                        horizontal: ChatScrollHintTokens.horizontalPadding.w,
                        vertical: ChatScrollHintTokens.verticalPadding.h,
                      ),
                      decoration: BoxDecoration(
                        color: ChatScrollHintTokens.background,
                        borderRadius: radius,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.keyboard_double_arrow_down,
                            color: ChatScrollHintTokens.foreground,
                            size: ChatScrollHintTokens.iconSize.r,
                          ),
                          AppTokens.s2.horizontalSpace,
                          Flexible(
                            child: Text(label,
                                style: Styles.ts_FFFFFF_14sp_medium.copyWith(
                                  color: ChatScrollHintTokens.foreground,
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                )),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
