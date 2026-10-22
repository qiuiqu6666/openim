import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../res/app_tokens.dart';
import '../../progress/sector_progress_painter.dart';
import '../chat_delayed_status_view.dart';

enum ChatTransferStage { queued, uploading, confirming, unknown }

@immutable
class ChatTransferStatus {
  const ChatTransferStatus(this.stage, [this.percent]);
  final ChatTransferStage stage;
  final int? percent;
}

/// Rebuilds only the sending indicator on every upload tick.
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
          final statusColor =
              color ?? Theme.of(context).colorScheme.onSurfaceVariant;
          if (value?.stage == ChatTransferStage.uploading) {
            final percent = value!.percent?.clamp(0, 100);
            return Semantics(
              label: 'chatMediaUploading'.tr,
              value: percent == null ? null : '$percent%',
              child: SizedBox.square(
                dimension: AppTokens.s8,
                child: CustomPaint(
                  painter: SectorProgressPainter(
                    progress: percent == null ? null : percent / 100,
                    color: statusColor,
                  ),
                  child: percent == null
                      ? Icon(Icons.file_upload_outlined,
                          color: statusColor, size: AppTokens.s5)
                      : null,
                ),
              ),
            );
          }
          if (value == null || value.stage == ChatTransferStage.confirming) {
            return Semantics(
              label: 'chatSendConfirming'.tr,
              child: ChatDelayedStatusView(
                isSending: true,
                color: statusColor,
              ),
            );
          }
          final label = switch (value.stage) {
            ChatTransferStage.queued => 'chatMediaQueued'.tr,
            ChatTransferStage.uploading => value.percent == null
                ? 'chatMediaUploading'.tr
                : '${'chatMediaUploading'.tr} ${value.percent}%',
            ChatTransferStage.unknown => 'chatSendCheck'.tr,
            _ => 'chatSendConfirming'.tr,
          };
          return GestureDetector(
            onTap: value.stage == ChatTransferStage.unknown ? onCheck : null,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: statusColor)),
          );
        },
      );
}
