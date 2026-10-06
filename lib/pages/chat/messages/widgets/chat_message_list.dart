import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat_logic.dart';
import '../../navigation/chat_message_focus_tokens.dart';
import '../selection/message_selection_drag_region.dart';
import '../selection/message_selection_row.dart';
import '../arrival/chat_message_arrival_animations.dart';
import 'chat_message_tile.dart';

/// Shared SDK timeline: route-specific presentation keeps pagination, receipts,
/// selection, viewport tracking and scroll ownership with the existing chat.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList(
      {super.key,
      required this.logic,
      this.messageBuilder,
      this.emptyView,
      this.latestRows = const []});

  final ChatLogic logic;
  final Widget Function(BuildContext, Message)? messageBuilder;
  final Widget? emptyView;
  // Presentation-only rows share the viewport, but never selection or receipts.
  final List<ChatTransientRow> latestRows;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList>
    with TickerProviderStateMixin {
  ChatLogic get logic => widget.logic;
  late ChatMessageArrivalAnimations _arrivals;

  void _arrivalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _arrivals = ChatMessageArrivalAnimations(
        vsync: this, arrivals: logic.messageArrivals);
    logic.messageArrivals.addListener(_arrivalChanged);
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logic != logic) {
      oldWidget.logic.messageArrivals.removeListener(_arrivalChanged);
      _arrivals.dispose();
      _attach();
    }
  }

  @override
  void dispose() {
    logic.messageArrivals.removeListener(_arrivalChanged);
    _arrivals.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    logic.bindMessageRoute(ModalRoute.of(context));
    final motionEnabled = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent != false;
    return Obx(() {
      final latestRows = widget.latestRows;
      final sdkCount = logic.messageList.length;
      final focusedID = logic.focusedMessageID.value;
      final count = sdkCount + latestRows.length;
      final sdkIDs = List<String>.generate(sdkCount,
          (index) => logic.messageList[sdkCount - 1 - index].clientMsgID ?? '');
      final sdkIndices = {
        for (var index = 0; index < sdkCount; index++) sdkIDs[index]: index,
      };
      final transientSlots = <int, List<ChatTransientRow>>{};
      for (final row in latestRows) {
        final anchor = sdkIndices[row.anchorMessageID];
        final slot = anchor == null ? 0 : anchor + (row.beforeAnchor ? 1 : 0);
        (transientSlots[slot] ??= []).add(row);
      }
      final messageIDs = [
        for (var index = 0; index <= sdkCount; index++) ...[
          ...?transientSlots[index]?.map((row) => row.id),
          if (index < sdkCount) sdkIDs[index],
        ],
      ];
      final transientByID = {for (final row in latestRows) row.id: row};
      final persistedIDs = sdkIDs.toSet();
      _arrivals.sync(persistedIDs, enabled: motionEnabled);
      final indices = <String, int>{
        for (var index = 0; index < count; index++)
          if (messageIDs[index].isNotEmpty) messageIDs[index]: index,
      };
      return NotificationListener<ScrollNotification>(
        onNotification: logic.onChatScrollNotification,
        child: MessageSelectionDragRegion(
          controller: logic.messageSelection,
          scrollController: logic.scrollController,
          child: ChatListView(
            emptyView: widget.emptyView,
            onTouch: logic.closeToolbox,
            itemCount: count,
            messageIDs: messageIDs,
            onViewportChanged: (ids, distance) => logic.onChatViewportChanged(
                ids.where(persistedIDs.contains).toList(), distance),
            controller: logic.scrollController,
            positionController: logic.messagePositionController,
            onScrollToBottomLoad: logic.onScrollToBottomLoad,
            enabledScrollTopLoad: logic.historyNewerHasMore.value,
            newerHasMore: logic.historyNewerHasMore.value,
            pagingWindow: logic.historyWindowRevision.value,
            onScrollToTopLoad: logic.onScrollToTopLoad,
            onScrollToTop: logic.onScrollToTop,
            loadOnInit: false,
            initialLoading: logic.initialHistoryLoading.value,
            historyLoading: logic.historyLoading.value,
            historyError: logic.historyError.value,
            hasMore: logic.historyHasMore.value,
            onRetry: logic.retryHistory,
            findChildIndexCallback: (key) =>
                key is ValueKey<String> ? indices[key.value] : null,
            itemBuilder: (context, index) {
              final id = messageIDs[index];
              final row = transientByID[id];
              if (row != null) {
                return KeyedSubtree(key: ValueKey(row.id), child: row.child);
              }
              final message = logic.indexOfMessage(sdkIndices[id]!);
              return KeyedSubtree(
                key: logic.itemKey(message),
                child: _arrivals.wrap(
                    id,
                    ColoredBox(
                      color: id == focusedID
                          ? AppTokens.accent.withValues(
                              alpha: ChatMessageFocusTokens.highlightOpacity)
                          : Colors.transparent,
                      child: MessageSelectionRow(
                        controller: logic.messageSelection,
                        message: message,
                        child: widget.messageBuilder?.call(context, message) ??
                            ChatMessageTile(logic: logic, message: message),
                      ),
                    )),
              );
            },
          ),
        ),
      );
    });
  }
}

/// A stable viewport identity, independent of persisted SDK message IDs.
class ChatTransientRow {
  const ChatTransientRow(
      {required this.id,
      required this.child,
      this.anchorMessageID,
      this.beforeAnchor = false});

  final String id;
  final Widget child;
  final String? anchorMessageID;
  // Before/after refer to chronological reading order, not the reversed list.
  final bool beforeAnchor;
}
