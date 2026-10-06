import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// 99chat's delete confirmation uses the native bottom action sheet.
abstract final class MessageSelectionDeleteSheet {
  static Future<bool> show(BuildContext context, int count) async {
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        key: const ValueKey('message-selection-delete-sheet'),
        title: Text('chatSelectionDeleteConfirm'.trParams({'count': '$count'})),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(StrRes.delete),
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
