import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../auth_copy.dart';

BuildContext? _noticeContext;

/// Uses the shared alert for authentication request feedback.
Future<void> showAuthNotice(String message) async {
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
    await showAppAlert<void>(
      context,
      title: authText('提示', 'Notice'),
      message: message,
      actions: [AppAction(StrRes.determine, null)],
    );
  } finally {
    if (identical(_noticeContext, context)) _noticeContext = null;
  }
}
