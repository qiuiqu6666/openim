import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'message_selection_controller.dart';
import 'message_selection_tokens.dart';

class MessageSelectionToolbar extends StatelessWidget {
  const MessageSelectionToolbar({super.key, required this.controller});
  final MessageSelectionController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => GlassAppBar(
          toolbarHeight: TitleBar.chatToolbarHeight,
          automaticallyImplyLeading: false,
          leadingWidth: MessageSelectionTokens.toolbarSide,
          leading: TextButton(
            key: const ValueKey('message-selection-cancel'),
            onPressed: controller.cancel,
            style: _buttonStyle(context),
            child: Text(StrRes.cancel,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          centerTitle: true,
          title: Text(
            controller.count == 0
                ? 'chatSelectionTitle'.tr
                : 'chatSelectionCount'
                    .trParams({'count': '${controller.count}'}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: MessageSelectionTokens.titleSize,
                fontWeight: FontWeight.w600),
          ),
          actions: const [
            SizedBox(width: MessageSelectionTokens.toolbarSide),
          ],
        ),
      );

  ButtonStyle _buttonStyle(BuildContext context) => TextButton.styleFrom(
        foregroundColor: AppTokens.accent,
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: MessageSelectionTokens.titleSize,
            fontWeight: FontWeight.w400),
      );
}
