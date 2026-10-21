import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// Local preparation feedback; the SDK message bubble owns upload and retry.
class ChatMediaPreparationIndicator extends StatelessWidget {
  const ChatMediaPreparationIndicator(
      {super.key,
      required this.count,
      this.failedCount = 0,
      this.onRetry,
      this.stageLabel,
      this.onCancel,
      this.onRetryOriginal});

  final int count;
  final int failedCount;
  final VoidCallback? onRetry, onCancel, onRetryOriginal;
  final String? stageLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.35),
          child: SingleChildScrollView(
            child: Padding(
              key: const ValueKey('chat-media-preparing'),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s4, vertical: AppTokens.s3),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (count > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LoadingView.indicator(
                          size: AppTokens.s5,
                          style: LoadingIndicatorStyle.ring),
                      const SizedBox(width: AppTokens.s3),
                      Flexible(
                        child: Text(
                          stageLabel ??
                              'chatMediaPreparing'
                                  .trParams({'count': '$count'}),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: AppTokens.textSecondary(
                                      dark: Theme.of(context).brightness ==
                                          Brightness.dark)),
                        ),
                      ),
                    ],
                  ),
                if (count > 0 && onCancel != null)
                  TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                          minimumSize: const Size(AppTokens.minimumTapSize,
                              AppTokens.minimumTapSize)),
                      child: Text('chatMediaCancelPending'.tr)),
                if (failedCount > 0)
                  Row(children: [
                    Expanded(
                        child: Text(
                            'chatMediaPreparationFailed'
                                .trParams({'count': '$failedCount'}),
                            style: Theme.of(context).textTheme.bodySmall)),
                    TextButton(
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                            minimumSize: const Size(AppTokens.minimumTapSize,
                                AppTokens.minimumTapSize)),
                        child: Text('chatMediaPreparationRetry'.tr)),
                  ]),
                if (failedCount > 0 && onRetryOriginal != null)
                  TextButton(
                      onPressed: onRetryOriginal,
                      style: TextButton.styleFrom(
                          minimumSize: const Size(AppTokens.minimumTapSize,
                              AppTokens.minimumTapSize)),
                      child: Text('chatMediaRetryOriginalVideo'.tr)),
              ]),
            ),
          ),
        ),
      );
}
