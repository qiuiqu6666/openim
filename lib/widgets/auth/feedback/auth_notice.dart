import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../auth_copy.dart';

BuildContext? _noticeContext;

/// Uses the shared alert for authentication request feedback.
Future<void> showAuthNotice(String message, {VoidCallback? onConfirmed}) async {
  final context = Get.context;
  if (message.trim().isEmpty ||
      context == null ||
      !context.mounted ||
      _noticeContext?.mounted == true) {
    return;
  }
  _noticeContext = context;
  FocusManager.instance.primaryFocus?.unfocus();
  try {
    if (onConfirmed == null) {
      await showAppAlert<void>(
        context,
        title: authText('提示', 'Notice'),
        message: message,
        actions: [AppAction(StrRes.determine, null)],
      );
      return;
    }
    final confirmed = await showAppAlert<bool>(
      context,
      title: authText('提示', 'Notice'),
      message: message,
      actions: [AppAction(StrRes.determine, true)],
    );
    if (confirmed == true) onConfirmed();
  } finally {
    // Identity comparison only; no widget-tree access after the dialog closes.
    // ignore: use_build_context_synchronously
    if (identical(_noticeContext, context)) _noticeContext = null;
  }
}
