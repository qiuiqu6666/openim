import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../auth_copy.dart';

bool _visible = false;

/// Uses the shared alert for authentication request feedback.
Future<void> showAuthNotice(String message) async {
  final context = Get.context;
  if (message.trim().isEmpty || context == null || !context.mounted || _visible) {
    return;
  }
  _visible = true;
  FocusManager.instance.primaryFocus?.unfocus();
  try {
    await showAppAlert<void>(
      context,
      title: authText('提示', 'Notice'),
      message: message,
      actions: [AppAction(StrRes.determine, null)],
    );
  } finally {
    _visible = false;
  }
}
