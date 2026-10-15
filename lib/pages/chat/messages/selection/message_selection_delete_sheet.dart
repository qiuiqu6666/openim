import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../widgets/message_action_confirmation_sheet.dart';

/// 99chat's delete confirmation uses the native bottom action sheet.
abstract final class MessageSelectionDeleteSheet {
  static Future<bool> show(BuildContext context, int count,
      {bool singleMessage = false}) async {
    return MessageActionConfirmationSheet.show(context,
        sheetKey: const ValueKey('message-selection-delete-sheet'),
        title: singleMessage
            ? 'chatMessageDeleteConfirm'.tr
            : 'chatSelectionDeleteConfirm'.trParams({'count': '$count'}),
        action: StrRes.delete);
  }
}
