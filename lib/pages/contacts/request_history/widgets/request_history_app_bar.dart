import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// Equal action widths keep the title centered with localized clear labels.
class RequestHistoryAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const RequestHistoryAppBar({
    super.key,
    required this.title,
    required this.confirmation,
    required this.onClear,
    required this.enabled,
  });

  final String title;
  final String confirmation;
  final Future<void> Function() onClear;
  final bool enabled;

  @override
  Size get preferredSize =>
      Size.fromHeight(NavigationGlassTokens.toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final label = TextPainter(
      text: TextSpan(text: StrRes.clearAll, style: Styles.ts_0089FF_14sp),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = math.min(
        math.max(kMinInteractiveDimension, label.width + AppTokens.s5.w),
        (MediaQuery.sizeOf(context).width - AppTokens.s5.w * 2) / 3);
    label.dispose();
    return TitleBar(
      left: SizedBox(
        width: width,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            padding: EdgeInsets.zero,
            onPressed: () => Get.back(),
            icon: ImageRes.backBlack.toImage
              ..width = AppTokens.s7.w
              ..height = AppTokens.s7.h
              ..color = Styles.c_0089FF,
          ),
        ),
      ),
      center: Expanded(
        child: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Styles.ts_0C1C33_17sp_semibold),
      ),
      right: SizedBox(
        width: width,
        child: TextButton(
          key: const ValueKey('request-history-clear'),
          style: TextButton.styleFrom(
            foregroundColor: Styles.c_0089FF,
            disabledForegroundColor: Styles.c_8E9AB0,
            textStyle: Styles.ts_0089FF_14sp,
            padding: EdgeInsets.zero,
          ),
          onPressed: !enabled
              ? null
              : () async {
                  final accepted = await Get.dialog<bool>(CustomDialog(
                    title: confirmation,
                    rightText: StrRes.clearAll,
                  ));
                  if (accepted == true && context.mounted) await onClear();
                },
          child: FittedBox(
              fit: BoxFit.scaleDown, child: Text(StrRes.clearAll, maxLines: 1)),
        ),
      ),
    );
  }
}
