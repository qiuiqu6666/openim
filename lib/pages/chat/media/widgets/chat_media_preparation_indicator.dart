import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// Local preparation feedback; the SDK message bubble owns upload and retry.
class ChatMediaPreparationIndicator extends StatelessWidget {
  const ChatMediaPreparationIndicator({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Padding(
          key: const ValueKey('chat-media-preparing'),
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s4, vertical: AppTokens.s3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LoadingView.indicator(
                  size: AppTokens.s5, style: LoadingIndicatorStyle.ring),
              const SizedBox(width: AppTokens.s3),
              Flexible(
                child: Text(
                  'chatMediaPreparing'.trParams({'count': '$count'}),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTokens.textSecondary(
                          dark:
                              Theme.of(context).brightness == Brightness.dark)),
                ),
              ),
            ],
          ),
        ),
      );
}
