import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../presentation/request_history_labels.dart';
import '../presentation/request_history_style.dart';

class RequestHistoryAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const RequestHistoryAppBar({
    super.key,
    required this.title,
    required this.confirmation,
    required this.onClear,
    required this.enabled,
    this.actions,
  });

  final String title;
  final String confirmation;
  final Future<void> Function() onClear;
  final bool enabled;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _showMore(BuildContext context) async {
    final clear = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            key: const ValueKey('request-history-clear'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, true),
            child: Text(RequestHistoryLabels.clearGroups),
          )
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, false),
          child: Text(StrRes.cancel),
        ),
      ),
    );
    if (clear != true || !context.mounted) return;
    final accepted = await Get.dialog<bool>(CustomDialog(
      title: confirmation,
      rightText: StrRes.clearAll,
    ));
    if (accepted == true && context.mounted) await onClear();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final count = actions?.length ?? 0;
    final sideWidth = count == 0
        ? kToolbarHeight
        : (RequestHistoryStyle.actionWidth *
                count *
                MediaQuery.textScalerOf(context)
                    .scale(AppTokens.captionFontSize) /
                AppTokens.captionFontSize)
            .clamp(kToolbarHeight, width * (count > 1 ? .4 : .25));
    return AppBar(
      backgroundColor: RequestHistoryStyle.surface(context),
      foregroundColor: AppTokens.accent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leadingWidth: sideWidth,
      leading: Align(
          alignment: AlignmentDirectional.centerStart,
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: RequestHistoryStyle.backIcon),
          )),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: RequestHistoryStyle.title(context).copyWith(
              fontSize: RequestHistoryStyle.headingSize,
              fontWeight: FontWeight.w700)),
      actions: actions == null
          ? [
              IconButton(
                key: const ValueKey('request-history-more'),
                tooltip: RequestHistoryLabels.more,
                onPressed: enabled ? () => _showMore(context) : null,
                icon: const Icon(Icons.more_horiz),
              )
            ]
          : [
              SizedBox(
                  width: sideWidth,
                  child: Row(children: [
                    for (final action in actions!) Expanded(child: action)
                  ]))
            ],
    );
  }
}
