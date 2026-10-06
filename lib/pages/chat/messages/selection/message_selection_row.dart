import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'message_selection_controller.dart';
import 'message_selection_layout.dart';
import 'message_selection_tokens.dart';

/// Keep the existing bubble mounted when entering/leaving selection, including
/// its media, visibility callbacks and read receipt lifecycle.
class MessageSelectionRow extends StatelessWidget {
  const MessageSelectionRow({
    super.key,
    required this.controller,
    required this.message,
    required this.child,
  });
  final MessageSelectionController controller;
  final Message message;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        child: child,
        builder: (context, child) {
          final selecting = controller.active &&
              MessageSelectionController.canSelect(message);
          final selected = controller.isSelected(message);
          return Semantics(
            container: selecting,
            checked: selecting ? selected : null,
            label: selecting
                ? '${'chatSelectionMessage'.tr}，${message.senderNickname ?? ''}，${IMUtils.parseMsg(message)}'
                : null,
            onTap: selecting && !controller.busy
                ? () => controller.toggle(message)
                : null,
            child: GestureDetector(
              key: ValueKey('message-selection-row-${message.clientMsgID}'),
              behavior: HitTestBehavior.opaque,
              onTap: selecting && !controller.busy
                  ? () => controller.toggle(message)
                  : null,
              child: MessageSelectionLayout(
                messageID: message.clientMsgID ?? '',
                selecting: selecting,
                indicator: Container(
                  key: ValueKey(
                      'message-selection-check-${message.clientMsgID}'),
                  width: MessageSelectionTokens.indicatorSize,
                  height: MessageSelectionTokens.indicatorSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? AppTokens.accent
                        : MessageSelectionTokens.unselected(context),
                    border: Border.all(
                      color: selected
                          ? AppTokens.accent
                          : MessageSelectionTokens.border(context),
                      width: MessageSelectionTokens.indicatorBorder,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check,
                          size: MessageSelectionTokens.checkSize,
                          color: AppTokens.onAccent)
                      : null,
                ),
                child: IgnorePointer(
                  ignoring: controller.active,
                  child: ExcludeSemantics(
                    excluding: selecting,
                    child: child!,
                  ),
                ),
              ),
            ),
          );
        },
      );
}
