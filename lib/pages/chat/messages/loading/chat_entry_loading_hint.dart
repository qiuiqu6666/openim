import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// A quiet status, with no fake message geometry or repeating animation.
class ChatEntryLoadingHint extends StatelessWidget {
  const ChatEntryLoadingHint({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(AppTokens.s4),
          child: Semantics(
            liveRegion: true,
            child: Text('chatHistoryLoading'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTokens.textSecondary(
                        dark:
                            Theme.of(context).brightness == Brightness.dark))),
          ),
        ),
      );
}
