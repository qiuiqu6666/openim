import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../models/ai_assistant_models.dart';
import '../ai_assistant_widgets.dart';

/// History owns lazy rows; focus, routing and data fetching stay with the page.
class AiAssistantMessageList extends StatelessWidget {
  const AiAssistantMessageList(
      {super.key,
      required this.dark,
      required this.messages,
      required this.historyLoaded,
      required this.welcomeVisible,
      required this.scrollController,
      required this.positions,
      required this.onStart,
      required this.onDismissWelcome,
      required this.messageBuilder});
  final bool dark, historyLoaded, welcomeVisible;
  final List<AiAssistantMessage> messages;
  final ItemScrollController scrollController;
  final ItemPositionsListener positions;
  final VoidCallback onStart, onDismissWelcome;
  final Widget Function(AiAssistantMessage) messageBuilder;

  @override
  Widget build(BuildContext context) {
    final i18n = AiAssistantI18n.of(context);
    if (historyLoaded && messages.isEmpty) {
      return AiEmptyChatArt(dark: dark, i18n: i18n, onStart: onStart);
    }
    return ScrollablePositionedList.builder(
      itemScrollController: scrollController,
      itemPositionsListener: positions,
      reverse: true,
      addAutomaticKeepAlives: false,
      padding: const EdgeInsets.fromLTRB(AiMetrics.space16, AiMetrics.space12,
          AiMetrics.space16, AiMetrics.space12),
      itemCount: messages.length + (welcomeVisible ? 1 : 0),
      itemBuilder: (_, index) {
        if (index == messages.length) {
          return Padding(
              padding: const EdgeInsets.only(top: AiMetrics.space12),
              child: AiWelcomeBanner(
                  dark: dark, i18n: i18n, onClose: onDismissWelcome));
        }
        return Padding(
            padding: const EdgeInsets.only(bottom: AiMetrics.space12),
            child: messageBuilder(messages[messages.length - 1 - index]));
      },
    );
  }
}
