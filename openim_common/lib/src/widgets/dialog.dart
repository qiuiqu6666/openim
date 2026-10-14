import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

export 'forward/forward_hint_dialog.dart';

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
  Widget build(BuildContext context) => AppAlertDialog<bool>(
        title: title ?? '',
        message: content,
        actions: [
          AppAction(leftText ?? StrRes.cancel, false),
          AppAction(rightText ?? StrRes.determine, true),
        ],
        onSelected: (confirmed) {
          if (confirmed) {
            (onTapRight ?? () => Get.back(result: true))();
          } else {
            (onTapLeft ?? () => Get.back(result: false))();
          }
        },
      );
}
