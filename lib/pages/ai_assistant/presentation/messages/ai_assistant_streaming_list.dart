import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../chat/chat_logic.dart';
import '../../../chat/messages/widgets/chat_message_list.dart';
import '../../streaming/assistant_stream_chunk.dart';
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

  List<String> _visibleStreams() {
    final snapshots = widget.logic.assistantStreams.snapshots;
    for (final snapshot in snapshots) {
      _replyOrder.putIfAbsent(snapshot.streamID, () => _replyOrder.length);
    }
    return snapshots
        .where((snapshot) => snapshot.text.isNotEmpty)
        .map((snapshot) => snapshot.streamID)
        .toList()
        .reversed
        .toList();
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
  Widget build(BuildContext context) => Obx(() => ChatMessageList(
        logic: widget.logic,
        emptyView: widget.emptyView,
        latestRows: widget.logic.bufferingLiveMessages
            ? const []
            : [
                for (final id in _streamIDs) _streamRow(id),
              ],
        messageBuilder: (context, message) => AiOpenIMMessageTile(
            logic: widget.logic, message: message, query: widget.query),
      ));

  ChatTransientRow _streamRow(String id) {
    final order = _replyOrder[id]!;
    String? anchor;
    int? anchorOrder;
    // Completed concurrent turns remain next to the same live previews.
    // This ordering belongs only to the presentation, never the SDK timeline.
    for (final message in widget.logic.messageList) {
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
      id: 'assistant-stream:$id',
      anchorMessageID: anchor,
      beforeAnchor: anchorOrder != null && anchorOrder > order,
      child: AiAssistantStreamTile(
          key: ValueKey('assistant-stream:$id'),
          streams: widget.logic.assistantStreams,
          streamID: id,
          query: widget.query),
    );
  }
}
