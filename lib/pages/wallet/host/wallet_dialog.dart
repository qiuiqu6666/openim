import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppDialog {
  AppDialog._();

  static Future<void> alert({
    required String title,
    required String message,
    String buttonText = '知道了',
    bool barrierDismissible = true,
  }) async {
    final context = Get.overlayContext ?? Get.context;
    if (context == null) return;
    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: true,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }
}
