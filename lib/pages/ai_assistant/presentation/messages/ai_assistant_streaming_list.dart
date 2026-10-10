import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

import '../../../chat/chat_logic.dart';
import '../../../chat/messages/widgets/chat_message_list.dart';
import '../../streaming/assistant_stream_chunk.dart';
import '../../theme/ai_palette.dart';
import 'ai_assistant_stream_tile.dart';
import 'ai_openim_message_tile.dart';

/// Only row appearance/removal rebuilds SDK indices; deltas update their bubble.
class AiAssistantStreamingList extends StatefulWidget {
  const AiAssistantStreamingList(
      {super.key,
      required this.logic,
      required this.emptyView,
      this.query = ''});

  final ChatLogic logic;
  final Widget emptyView;
  final String query;

  @override
  State<AiAssistantStreamingList> createState() =>
      _AiAssistantStreamingListState();
}

class _AiAssistantStreamingListState extends State<AiAssistantStreamingList> {
  List<String> _streamIDs = const [];
  final _replyOrder = <String, int>{};
  final _presentationOrder = <String, int>{};

  List<String> _visibleStreams() {
    final snapshots = widget.logic.assistantStreams.snapshots;
    for (final snapshot in snapshots) {
      final order = _presentationOrder.putIfAbsent(
          snapshot.presentationID, () => _presentationOrder.length);
      _replyOrder[snapshot.streamID] = order;
    }
    return [
      ...snapshots
          .where((snapshot) => snapshot.waiting)
          .map((snapshot) => snapshot.streamID),
      ...snapshots
          .where((snapshot) => !snapshot.waiting && snapshot.text.isNotEmpty)
          .map((snapshot) => snapshot.streamID)
          .toList()
          .reversed,
    ];
  }

  @override
  void initState() {
    super.initState();
    _streamIDs = _visibleStreams();
    widget.logic.assistantStreams.addListener(_streamsChanged);
  }

  @override
  void didUpdateWidget(covariant AiAssistantStreamingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logic != widget.logic) {
      oldWidget.logic.assistantStreams.removeListener(_streamsChanged);
      _replyOrder.clear();
      _presentationOrder.clear();
      _streamIDs = _visibleStreams();
      widget.logic.assistantStreams.addListener(_streamsChanged);
    }
  }

  void _streamsChanged() {
    final next = _visibleStreams();
    if (mounted && !listEquals(_streamIDs, next)) {
      setState(() => _streamIDs = next);
    }
  }

  @override
  void dispose() {
    widget.logic.assistantStreams.removeListener(_streamsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Obx(() {
          final buffering = widget.logic.bufferingLiveMessages;
          final localIDs = buffering
              ? widget.logic.assistantStreams.snapshots
                  .where((snapshot) =>
                      snapshot.rowID != null &&
                      (snapshot.waiting || snapshot.text.isNotEmpty))
                  .map((snapshot) => snapshot.streamID)
                  .toSet()
              : const <String>{};
          final localRows =
              _streamIDs.where(localIDs.contains).toList().reversed;
          return Column(
            children: [
              // Keep one viewport mounted through every window transition.
              Expanded(
                child: ChatMessageList(
                  logic: widget.logic,
                  emptyView: widget.emptyView,
                  latestRows: buffering
                      ? const []
                      : [
                          for (final id in _streamIDs) _streamRow(id),
                        ],
                  messageBuilder: (context, message) => AiOpenIMMessageTile(
                      logic: widget.logic,
                      message: message,
                      query: widget.query),
                ),
              ),
              if (localRows.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: (constraints.maxHeight / 2)
                          .clamp(AiMetrics.space0, AiMetrics.dimension180)
                          .toDouble()),
                  child: Padding(
                    padding: const EdgeInsets.only(top: AiMetrics.space8),
                    child: SingleChildScrollView(
                      primary: false,
                      reverse: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final id in localRows) _streamRow(id).child,
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      );

  ChatTransientRow _streamRow(String id) {
    final snapshot = widget.logic.assistantStreams.snapshots
        .firstWhere((snapshot) => snapshot.streamID == id);
    final presentationID = snapshot.presentationID;
    final order = _replyOrder[id]!;
    String? anchor;
    int? anchorOrder;
    // Completed concurrent turns remain next to the same live previews.
    // This ordering belongs only to the presentation, never the SDK timeline.
    for (final message
        in snapshot.waiting ? const <Message>[] : widget.logic.messageList) {
      final finalID = AssistantStreamChunk.finalStreamID(message);
      final candidate = _replyOrder[finalID];
      if (candidate == null || message.clientMsgID == null) continue;
      if (anchorOrder == null ||
          (candidate > order &&
              (anchorOrder < order || candidate < anchorOrder)) ||
          (candidate < order &&
              anchorOrder < order &&
              candidate > anchorOrder)) {
        anchor = message.clientMsgID;
        anchorOrder = candidate;
      }
    }
    return ChatTransientRow(
      id: 'assistant-stream:$presentationID',
      anchorMessageID: anchor,
      beforeAnchor: anchorOrder != null && anchorOrder > order,
      child: AiAssistantStreamTile(
          key: ValueKey('assistant-stream:$presentationID'),
          streams: widget.logic.assistantStreams,
          streamID: id,
          presentationID: presentationID,
          query: widget.query),
    );
  }
}
