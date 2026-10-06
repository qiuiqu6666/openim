import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

enum DialogType {
  confirm,
}

class CustomDialog extends StatelessWidget {
  const CustomDialog({
    Key? key,
    this.title,
    this.url,
    this.content,
    this.rightText,
    this.leftText,
    this.onTapLeft,
    this.onTapRight,
  }) : super(key: key);
  final String? title;
  final String? url;
  final String? content;
  final String? rightText;
  final String? leftText;
  final Function()? onTapLeft;
  final Function()? onTapRight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: Container(
            width: 280.w,
            color: Styles.c_FFFFFF,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 20.h,
                  ),
                  child: Text(
                    title ?? '',
                    style: Styles.ts_0C1C33_17sp,
                  ),
                ),
                Divider(
                  color: Styles.c_E8EAEF,
                  height: 0.5.h,
                ),
                Row(
                  children: [
                    _button(
                      bgColor: Styles.c_FFFFFF,
                      text: leftText ?? StrRes.cancel,
                      textStyle: Styles.ts_0C1C33_17sp,
                      onTap: onTapLeft ?? () => Get.back(result: false),
                    ),
                    Container(
                      color: Styles.c_E8EAEF,
                      width: 0.5.w,
                      height: 48.h,
                    ),
                    _button(
                      bgColor: Styles.c_FFFFFF,
                      text: rightText ?? StrRes.determine,
                      textStyle: Styles.ts_0089FF_17sp,
                      onTap: onTapRight ?? () => Get.back(result: true),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required Color bgColor,
    required String text,
    required TextStyle textStyle,
    Function()? onTap,
  }) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
            ),
            height: 48.h,
            alignment: Alignment.center,
            child: Text(
              text,
              style: textStyle,
            ),
          ),
        ),
      );
}

class ForwardHintDialog extends StatelessWidget {
  const ForwardHintDialog({
    Key? key,
    required this.title,
    this.checkedList = const [],
    this.nameBuilder,
    this.nameMinHeight = 0,
  }) : super(key: key);
  final String title;
  final List<dynamic> checkedList;

  /// Lets an application decorate a recipient name without adding business
  /// identity rules to this shared dialog. Receives the original SDK object.
  final Widget Function(BuildContext, dynamic recipient, TextStyle)?
      nameBuilder;
  final double nameMinHeight;

  Widget _name(BuildContext context, int index, String name, TextStyle style) =>
      nameBuilder?.call(context, checkedList[index], style) ??
      (name.toText
        ..style = style
        ..maxLines = 1
        ..overflow = TextOverflow.ellipsis);

  @override
  Widget build(BuildContext context) {
    final list = IMUtils.convertCheckedListToForwardObj(checkedList);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            margin: EdgeInsets.symmetric(horizontal: 36.w),
            decoration: BoxDecoration(
              color: Styles.c_FFFFFF,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                (list.length == 1 ? StrRes.sentTo : StrRes.sentSeparatelyTo)
                    .toText
                  ..style = Styles.ts_0C1C33_17sp_medium,
                5.verticalSpace,
                list.length == 1
                    ? Row(
                        children: [
                          AvatarView(
                            url: list.first['faceURL'],
                            text: list.first['nickname'],
                            isCircle: true,
                          ),
                          10.horizontalSpace,
                          Expanded(
                            child: _name(
                                context,
                                0,
                                list.first['nickname'] ?? '',
                                Styles.ts_0C1C33_17sp),
                          ),
                        ],
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 120.h),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final nicknameStyle = Styles.ts_8E9AB0_10sp;
                          var effectiveStyle = DefaultTextStyle.of(context)
                              .style
                              .merge(nicknameStyle);
                          if (MediaQuery.boldTextOf(context)) {
                            effectiveStyle = effectiveStyle.merge(
                                const TextStyle(fontWeight: FontWeight.bold));
                          }
                          final cellWidth =
                              (constraints.maxWidth - 4 * 10.w) / 5;
                          var nicknameHeight = 0.0;
                          for (final recipient in list) {
                            final painter = TextPainter(
                              text: TextSpan(
                                  text: recipient['nickname'] ?? '',
                                  style: effectiveStyle),
                              textDirection: Directionality.of(context),
                              textScaler: MediaQuery.textScalerOf(context),
                              locale: Localizations.localeOf(context),
                              maxLines: 1,
                              ellipsis: '…',
                            )..layout(maxWidth: cellWidth);
                            if (painter.height > nicknameHeight) {
                              nicknameHeight = painter.height;
                            }
                            painter.dispose();
                          }
                          if (nameMinHeight > nicknameHeight) {
                            nicknameHeight = nameMinHeight;
                          }
                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              crossAxisSpacing: 10.w,
                              mainAxisSpacing: 0,
                              mainAxisExtent:
                                  44.w + nicknameHeight + AppTokens.s2,
                            ),
                            itemCount: list.length,
                            shrinkWrap: true,
                            itemBuilder: (_, index) => Column(
                              children: [
                                AvatarView(
                                  url: list.elementAt(index)['faceURL'],
                                  text: list.elementAt(index)['nickname'],
                                  isCircle: true,
                                ),
                                const SizedBox(height: AppTokens.s2),
                                _name(
                                    context,
                                    index,
                                    list.elementAt(index)['nickname'] ?? '',
                                    nicknameStyle),
                              ],
                            ),
                          );
                        }),
                      ),
                5.verticalSpace,
                title.toText
                  ..style = Styles.ts_8E9AB0_14sp
                  ..maxLines = 1
                  ..overflow = TextOverflow.ellipsis,
                16.verticalSpace,
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 26.w,
                  overflowSpacing: AppTokens.s2,
                  children: [
                    StrRes.cancel.toText
                      ..style = Styles.ts_0C1C33_17sp
                      ..onTap = () => Get.back(),
                    StrRes.determine.toText
                      ..style = Styles.ts_0089FF_17sp
                      ..onTap = () => Get.back(result: true),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
