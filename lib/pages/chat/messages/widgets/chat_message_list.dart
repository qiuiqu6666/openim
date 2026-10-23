import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat_logic.dart';
import '../../fund/confirmed_fund_card_row.dart';
import '../../media/chat_image_prewarmer.dart';
import '../../media/preparation/pending_chat_media.dart';
import '../../media/widgets/pending_chat_media_bubble.dart';
import '../../navigation/chat_entry_route_timing.dart';
import '../../navigation/chat_message_focus_tokens.dart';
import '../selection/message_selection_drag_region.dart';
import '../selection/message_selection_row.dart';
import '../arrival/chat_message_arrival_animations.dart';
import 'chat_message_tile.dart';
import '../chat_message_index.dart';
import '../loading/chat_entry_loading_hint.dart';
import '../loading/chat_initial_window_transition.dart';

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  ChatImagePrewarmer _imagePrewarmer = ChatImagePrewarmer();
  ChatLogic get logic => widget.logic;
  late ChatMessageArrivalAnimations _arrivals;
  final _messageIndex = ChatMessageIndex();
  Worker? _indexWorker;
  bool _indexDirty = true;
  bool _hasPaintedMessages = false;
  final _entryTransitionKey = GlobalKey<ChatInitialWindowTransitionState>();

  void _arrivalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _indexDirty = true;
    _indexWorker = ever(logic.messageList, (_) => _indexDirty = true);
    _arrivals = ChatMessageArrivalAnimations(
        vsync: this, arrivals: logic.messageArrivals);
    logic.messageArrivals.addListener(_arrivalChanged);
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logic != logic) {
      _imagePrewarmer.dispose();
      _imagePrewarmer = ChatImagePrewarmer();
      _hasPaintedMessages = false;
      oldWidget.logic.messageArrivals.removeListener(_arrivalChanged);
      _arrivals.dispose();
      _indexWorker?.dispose();
      _attach();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _imagePrewarmer.dispose();
    _indexWorker?.dispose();
    logic.messageArrivals.removeListener(_arrivalChanged);
    _arrivals.dispose();
    super.dispose();
  }

  void _updateImageWarmupActivity() {
    _imagePrewarmer.setActive(logic.isMessageNavigationCurrent &&
        ModalRoute.of(context)?.isCurrent != false &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) _updateImageWarmupActivity();
  }

  @override
  Widget build(BuildContext context) {
    logic.bindMessageRoute(ModalRoute.of(context));
    _updateImageWarmupActivity();
    final motionEnabled = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent != false;
    return ChatEntryRouteTiming(
        trace: logic.entryTrace,
        child: Obx(() {
          // SDK state transitions invalidate receipt visibility even when rows and
          // their geometry stay unchanged. Rebuild the real viewport so it reports
          // a fresh painted observation after a sync/connection barrier changes.
          logic.syncStatus.value;
          final latestRows = [
            ...widget.latestRows,
            for (final pending in PendingChatMedia.entries.reversed)
              if (pending.conversationID ==
                      logic.conversationInfo.conversationID &&
                  pending.visible())
                ChatTransientRow(
                    id: pending.id,
                    child: PendingChatMediaBubble(
                        key: ValueKey(pending.id),
                        pending: pending,
                        isChannel: logic.isChannel)),
            if (!logic.viewingHistory.value && !logic.hasDeferredLatest)
              for (final card in logic.confirmedFundCards)
                ChatTransientRow(
                  id: card.id,
                  anchorMessageID: card.anchorMessageID,
                  child: ConfirmedFundCardRow(
                    card: card,
                    isGroup: logic.isGroupChat,
                    recipient: logic.fundCardRecipient(card.data),
                    packetCount: logic.fundPacketCount(card.data),
                    claimedByMe: logic.fundMessageClaimedByMe(card.data),
                    onTap: () => logic.openConfirmedFundCard(card.data),
                  ),
                ),
          ];
          final sdkCount =
              logic.initialWindowReady.value ? logic.messageList.length : 0;
          final count = sdkCount + latestRows.length;
          if (_indexDirty || _messageIndex.ids.length != sdkCount) {
            _messageIndex.sync(sdkCount == 0 ? <Message>[] : logic.messageList);
            _indexDirty = false;
          }
          final sdkIDs = _messageIndex.ids;
          final sdkIndices = _messageIndex.indices;
          final transientSlots = <int, List<ChatTransientRow>>{};
          for (final row in latestRows) {
            final anchor = sdkIndices[row.anchorMessageID];
            final slot =
                anchor == null ? 0 : anchor + (row.beforeAnchor ? 1 : 0);
            (transientSlots[slot] ??= []).add(row);
          }
          final messageIDs = latestRows.isEmpty
              ? sdkIDs
              : [
                  for (var index = 0; index <= sdkCount; index++) ...[
                    ...?transientSlots[index]?.map((row) => row.id),
                    if (index < sdkCount) sdkIDs[index],
                  ],
                ];
          final transientByID = {for (final row in latestRows) row.id: row};
          final persistedIDs = _messageIndex.persisted;
          _arrivals.sync(persistedIDs, enabled: motionEnabled);
          final indices = latestRows.isEmpty
              ? sdkIndices
              : <String, int>{
                  for (var index = 0; index < count; index++)
                    if (messageIDs[index].isNotEmpty) messageIDs[index]: index,
                };
          final initialLoading = !logic.initialWindowReady.value &&
              logic.historyError.value == null &&
              !logic.historyScanLimited.value;
          return ChatInitialWindowTransition(
            key: _entryTransitionKey,
            loading: initialLoading,
            loadingIndicator: const ChatEntryLoadingHint(),
            onRevealed: logic.messagePositionController.refreshViewport,
            observePaint: () => logic.entryTrace?.listInteractive != true,
            onContentPainted: logic.entryTrace == null
                ? null
                : (interactive) {
                    if (sdkCount > 0 && !_hasPaintedMessages) return;
                    logic.entryTrace?.painted(
                        publishable: logic.initialWindowReady.value,
                        hasVisibleMessages: _hasPaintedMessages,
                        contentVisible: true,
                        canInteract: interactive,
                        current: logic.isMessageNavigationCurrent);
                  },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) {
                  if (notification is ScrollStartNotification) {
                    _imagePrewarmer.setScrolling(true);
                  } else if (notification is ScrollEndNotification) {
                    _imagePrewarmer.setScrolling(false);
                  }
                }
                return logic.onChatScrollNotification(notification);
              },
              child: MessageSelectionDragRegion(
                controller: logic.messageSelection,
                scrollController: logic.scrollController,
                child: ChatListView(
                  emptyView: widget.emptyView,
                  onTouch: logic.closeToolbox,
                  itemCount: count,
                  messageIDs: messageIDs,
                  onViewportChanged: (ids, distance) {
                    _hasPaintedMessages = ids.any(persistedIDs.contains);
                    if (_entryTransitionKey.currentState?.canReportContent ==
                        true) {
                      logic.onChatViewportChanged(
                          ids.where(persistedIDs.contains).toList(), distance);
                      _imagePrewarmer.update(logic.messageList, ids);
                    }
                  },
                  controller: logic.scrollController,
                  positionController: logic.messagePositionController,
                  onScrollToBottomLoad: logic.onScrollToBottomLoad,
                  enabledScrollTopLoad: logic.historyNewerHasMore.value,
                  newerHasMore: logic.historyNewerHasMore.value,
                  pagingWindow: logic.historyWindowRevision.value,
                  onScrollToTopLoad: logic.onScrollToTopLoad,
                  onScrollToTop: logic.onScrollToTop,
                  loadOnInit: false,
                  followLatest:
                      !logic.viewingHistory.value && !logic.hasDeferredLatest,
                  initialLoading: logic.initialHistoryLoading.value,
                  initialLoadingView: const SizedBox.expand(),
                  historyLoading: logic.historyPagingLoading.value,
                  historyError: logic.historyError.value,
                  historyScanLimited: logic.historyScanLimited.value,
                  hasMore: logic.historyHasMore.value,
                  onRetry: logic.retryHistory,
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indices[key.value] : null,
                  itemBuilder: (context, index) {
                    final id = messageIDs[index];
                    final row = transientByID[id];
                    if (row != null) {
                      return KeyedSubtree(
                          key: ValueKey(row.id), child: row.child);
                    }
                    final message = logic.indexOfMessage(sdkIndices[id]!);
                    final messageRow = MessageSelectionRow(
                      controller: logic.messageSelection,
                      message: message,
                      child: widget.messageBuilder?.call(context, message) ??
                          ChatMessageTile(logic: logic, message: message),
                    );
                    return KeyedSubtree(
                      key: logic.itemKey(message),
                      child: _arrivals.wrap(
                          id,
                          Obx(() => ChatMessageHighlight(
                                active: id == logic.focusedMessageID.value,
                                color: AppTokens.accent.withValues(
                                    alpha: ChatMessageFocusTokens
                                        .highlightOpacity),
                                fadeDuration:
                                    ChatMessageFocusTokens.fadeDuration,
                                child: messageRow,
                              ))),
                    );
                  },
                ),
              ),
            ),
          );
        }));
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
