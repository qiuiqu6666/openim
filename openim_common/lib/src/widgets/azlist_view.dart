import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class WrapAzListView<T extends ISuspensionBean> extends StatelessWidget {
  const WrapAzListView({
    super.key,
    required this.data,
    required this.itemCount,
    required this.itemBuilder,
    this.susItemHeight,
    this.susTextStyle,
    this.indexBarItemHeight,
    this.indexBarWidth,
    this.indexBarOptions,
  });

  final List<T> data;
  final int itemCount;
  final Widget Function(BuildContext context, T data, int index) itemBuilder;
  final double? susItemHeight;
  final TextStyle? susTextStyle;
  final double? indexBarItemHeight;
  final double? indexBarWidth;
  final IndexBarOptions? indexBarOptions;

  @override
  Widget build(BuildContext context) {
    return AzListView(
      data: data,
      itemCount: itemCount,
      itemBuilder: (BuildContext context, int index) {
        var model = data[index];
        return itemBuilder(context, model, index);
      },
      susItemBuilder: (BuildContext context, int index) {
        var model = data[index];
        if ('↑' == model.getSuspensionTag()) {
          return Container();
        }
        return _buildTagView(model.getSuspensionTag());
      },
      susItemHeight: susItemHeight ?? 23.h,
      indexBarData: SuspensionUtil.getTagIndexList(data),
      indexBarItemHeight: indexBarItemHeight ?? kIndexBarItemHeight,
      indexBarWidth: indexBarWidth ?? kIndexBarWidth,
      indexBarOptions: indexBarOptions ??
          IndexBarOptions(
            needRebuild: true,
            selectTextStyle: Styles.ts_FFFFFF_12sp,
            indexHintWidth: 96,
            indexHintHeight: 97,
            indexHintDecoration: const BoxDecoration(
              image: DecorationImage(
                image:
                    AssetImage(ImageRes.indexBarBg, package: 'openim_common'),
                fit: BoxFit.contain,
              ),
            ),
            indexHintAlignment: Alignment.centerRight,
            indexHintTextStyle: Styles.ts_0C1C33_20sp_semibold,
            indexHintOffset: const Offset(-30, 0),
          ),
    );
  }

  Widget _buildTagView(String tag) => Container(
        height: susItemHeight ?? 23.h,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        alignment: Alignment.centerLeft,
        width: 1.sw,
        color: Styles.c_E8EAEF,
        child: tag.toText..style = susTextStyle ?? Styles.ts_8E9AB0_14sp,
      );
}

/// Shared alphabet navigation appearance used by the contacts directory.
IndexBarOptions directoryIndexBarOptions({
  TextStyle? textStyle,
  TextStyle? selectTextStyle,
  Color? accentColor,
  bool highlightSelection = false,
  bool hapticFeedback = false,
}) =>
    IndexBarOptions(
      needRebuild: true,
      hapticFeedback: hapticFeedback,
      textStyle: textStyle ?? Styles.ts_8E9AB0_12sp,
      selectTextStyle: selectTextStyle ?? Styles.ts_FFFFFF_12sp,
      downTextStyle: selectTextStyle ?? Styles.ts_FFFFFF_12sp,
      selectItemDecoration: highlightSelection
          ? BoxDecoration(
              color: accentColor ?? Styles.c_0089FF, shape: BoxShape.circle)
          : null,
      downItemDecoration: BoxDecoration(
          color: accentColor ?? Styles.c_0089FF, shape: BoxShape.circle),
      indexHintDecoration: BoxDecoration(
          color: accentColor ?? Styles.c_0089FF,
          borderRadius: BorderRadius.circular(12.r)),
    );
