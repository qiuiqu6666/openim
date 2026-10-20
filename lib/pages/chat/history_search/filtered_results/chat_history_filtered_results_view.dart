import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_history_search_controller.dart';
import '../chat_history_search_strings.dart';
import '../chat_history_search_tokens.dart';
import '../widgets/chat_history_result_tile.dart';
import '../widgets/chat_history_search_layout.dart';
import 'chat_history_filtered_results_tokens.dart';
import 'chat_history_opening_overlay.dart';

/// Presents member/day history; its parent owns SDK/session state and navigation.
class ChatHistoryFilteredResultsView extends StatelessWidget {
  const ChatHistoryFilteredResultsView({
    super.key,
    required this.controller,
    required this.pageKey,
    required this.title,
    required this.onMessage,
    required this.onRefresh,
    this.openingMessage = false,
  });

  final ChatHistorySearchController controller;
  final Key pageKey;
  final String title;
  final bool openingMessage;
  final ValueChanged<Message> onMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final header = ChatComposerTokens.surface(dark: dark);
    return Scaffold(
      key: pageKey,
      backgroundColor: ChatComposerTokens.background(dark: dark),
      appBar: AppBar(
        backgroundColor: header,
        systemOverlayStyle: AppSystemBars.styleFor(header),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: kToolbarHeight,
        leadingWidth: kToolbarHeight,
        centerTitle: true,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: AppTokens.chevronSize, color: AppTokens.accent),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: AppTokens.listTitleFontSize,
                fontWeight: chatHistorySearchIsDesktop(context)
                    ? FontWeight.w600
                    : FontWeight.w700,
                color: AppTokens.textPrimary(dark: dark))),
      ),
      body: ChatHistoryOpeningOverlay(
        opening: openingMessage,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (controller.loading && controller.results.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppTokens.accent,
                  strokeWidth:
                      ChatHistoryFilteredResultsTokens.progressStrokeWidth,
                ),
              );
            }
            if (controller.results.isEmpty &&
                (!controller.hasMore || controller.failed)) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chatHistorySearchText(
                          context,
                          controller.failed
                              ? 'failed'
                              : controller.hasMore
                                  ? 'moreMessages'
                                  : 'noData'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTokens.textSecondary(dark: dark)),
                    ),
                    if (controller.failed)
                      TextButton(
                        key: const ValueKey('chat-history-retry'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppTokens.accent),
                        onPressed: controller.retry,
                        child: Text(chatHistorySearchText(context, 'retry')),
                      ),
                    if (!controller.failed && controller.hasMore)
                      _footer(context),
                  ],
                ),
              );
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    notification.metrics.extentAfter < 160 &&
                    ((notification is ScrollUpdateNotification &&
                            (notification.scrollDelta ?? 0) > 0) ||
                        (notification is OverscrollNotification &&
                            notification.overscroll > 0)) &&
                    !controller.loading &&
                    !controller.failed &&
                    controller.hasMore) {
                  controller.loadMore();
                }
                return false;
              },
              child: RefreshIndicator(
                color: AppTokens.accent,
                backgroundColor: AppTokens.surface(dark: dark),
                onRefresh: onRefresh,
                child: ListView.builder(
                  key: const PageStorageKey('chat-history-results-list'),
                  padding: const EdgeInsets.only(bottom: AppTokens.s7),
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: controller.results.length + 1,
                  itemBuilder: (context, index) {
                    if (index == controller.results.length) {
                      return _footer(context);
                    }
                    final message = controller.results[index];
                    return ChatHistoryResultTile(
                      key: ValueKey(
                          'chat-history-result-${message.clientMsgID}'),
                      message: message,
                      horizontalPadding:
                          ChatHistorySearchTokens.horizontalPadding,
                      showDivider: true,
                      onTap: () => onMessage(message),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    if (controller.failed) {
      return Center(
          child: TextButton(
        key: const ValueKey('chat-history-retry'),
        onPressed: controller.retry,
        child: Text(chatHistorySearchText(context, 'retry')),
      ));
    }
    if (!controller.loading) return const SizedBox(height: AppTokens.s5);
    return const Padding(
      padding: EdgeInsets.all(AppTokens.s4),
      child: Center(
          child: SizedBox.square(
        dimension: ChatHistoryFilteredResultsTokens.moreProgressSize,
        child: CircularProgressIndicator(
            color: AppTokens.accent,
            strokeWidth: ChatHistoryFilteredResultsTokens.progressStrokeWidth),
      )),
    );
  }
}
