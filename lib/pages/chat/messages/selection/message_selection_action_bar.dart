import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'message_selection_controller.dart';
import 'message_selection_delete_sheet.dart';
import 'message_selection_tokens.dart';

class MessageSelectionActionBar extends StatelessWidget {
  const MessageSelectionActionBar({super.key, required this.controller});
  final MessageSelectionController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final enabled = controller.count > 0 && !controller.busy;
          return LiquidGlassSurface(
            surface: NavigationGlassSurface.bottom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: MessageSelectionTokens.dividerWidth)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
                  child: Row(
                    children: [
                      _action(context,
                          id: 'forward',
                          iconAsset: MessageSelectionTokens.forwardIcon,
                          label: 'chatSelectionForward'.tr,
                          enabled: enabled,
                          onPressed: () =>
                              controller.forwardSelected(merged: false)),
                      _action(context,
                          id: 'merge',
                          iconAsset: MessageSelectionTokens.mergeIcon,
                          label: 'sdkMergeForward'.tr,
                          enabled: enabled,
                          onPressed: () =>
                              controller.forwardSelected(merged: true)),
                      _action(context,
                          id: 'delete',
                          iconAsset: MessageSelectionTokens.deleteIcon,
                          label: StrRes.delete,
                          enabled: enabled,
                          onPressed: () => controller.deleteSelected(
                                confirm: (count) =>
                                    MessageSelectionDeleteSheet.show(
                                        context, count),
                              )),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _action(BuildContext context,
      {required String id,
      required String iconAsset,
      required String label,
      required bool enabled,
      required VoidCallback onPressed}) {
    final color = MessageSelectionTokens.foreground(context);
    final scaledHeight = MessageSelectionTokens.barHeight +
        (MediaQuery.textScalerOf(context)
                        .scale(MessageSelectionTokens.labelSize) -
                    MessageSelectionTokens.labelSize)
                .clamp(0, double.infinity) *
            2;
    return Expanded(
      child: TextButton(
        key: ValueKey('message-selection-$id'),
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: Size(0, scaledHeight),
          padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
          shape: const RoundedRectangleBorder(),
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: MessageSelectionTokens.labelSize,
              fontWeight: FontWeight.w400),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              iconAsset,
              width: MessageSelectionTokens.iconSize,
              height: MessageSelectionTokens.iconSize,
              color: enabled ? color : Theme.of(context).disabledColor,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: MessageSelectionTokens.labelGap),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
