import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_history_filtered_results_tokens.dart';

/// Route-local feedback: it never covers the next chat or blocks the back button.
class ChatHistoryOpeningOverlay extends StatelessWidget {
  const ChatHistoryOpeningOverlay(
      {super.key, required this.opening, required this.child});

  final bool opening;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      AbsorbPointer(absorbing: opening, child: child),
      if (opening)
        Center(
            child: Semantics(
                liveRegion: true,
                child: Card(
                  color: AppTokens.surface(dark: dark),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s5),
                    child: SizedBox.square(
                      dimension:
                          ChatHistoryFilteredResultsTokens.openingProgressSize,
                      child: CircularProgressIndicator(
                        key: const ValueKey('chat-history-opening-spinner'),
                        value: MediaQuery.disableAnimationsOf(context)
                            ? 0.75
                            : null,
                        color: AppTokens.accent,
                        strokeWidth: ChatHistoryFilteredResultsTokens
                            .progressStrokeWidth,
                        semanticsLabel: 'chatHistoryLoading'.tr,
                      ),
                    ),
                  ),
                ))),
    ]);
  }
}
