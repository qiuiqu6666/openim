import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum ChatTransferStage { queued, uploading, confirming, unknown }

@immutable
class ChatTransferStatus {
  const ChatTransferStatus(this.stage, [this.percent]);
  final ChatTransferStage stage;
  final int? percent;
}

/// Rebuilds only the sending label, not the conversation on every upload tick.
class ChatTransferStatusView extends StatelessWidget {
  const ChatTransferStatusView(
      {super.key, required this.status, this.color, this.onCheck});
  final ValueListenable<ChatTransferStatus?> status;
  final Color? color;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ChatTransferStatus?>(
        valueListenable: status,
        builder: (context, value, _) {
          final label = switch (value?.stage) {
            ChatTransferStage.queued => 'chatMediaQueued'.tr,
            ChatTransferStage.uploading => value?.percent == null
                ? 'chatMediaUploading'.tr
                : '${'chatMediaUploading'.tr} ${value!.percent}%',
            ChatTransferStage.unknown => 'chatSendCheck'.tr,
            _ => 'chatSendConfirming'.tr,
          };
          return GestureDetector(
            onTap: value?.stage == ChatTransferStage.unknown ? onCheck : null,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color ??
                        Theme.of(context).colorScheme.onSurfaceVariant)),
          );
        },
      );
}
