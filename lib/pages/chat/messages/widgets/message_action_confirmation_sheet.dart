import 'package:flutter/cupertino.dart';
import 'package:openim_common/openim_common.dart';

/// Shared confirmation for destructive message actions.
abstract final class MessageActionConfirmationSheet {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String action,
    required Key sheetKey,
  }) async {
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        key: sheetKey,
        title: Text(title),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, false),
          child: Text(StrRes.cancel),
        ),
      ),
    );
    return confirmed == true;
  }
}
