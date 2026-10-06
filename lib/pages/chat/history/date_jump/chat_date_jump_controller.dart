import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

typedef ChatDateMessageSearch = Future<SearchResult> Function({
  required String conversationID,
  required List<int> messageTypeList,
  required int searchTimePosition,
  required int searchTimePeriod,
  required int pageIndex,
  required int count,
});

/// Picks a local calendar day and delegates its anchor to the current timeline.
class ChatDateJumpController {
  ChatDateJumpController({
    required this.conversationID,
    required this.isClosed,
    required this.isRemoved,
    required this.search,
    required this.jumpToMessage,
    required this.showFeedback,
    required this.runLoading,
    List<Message> Function()? messages,
  }) : _messages = messages ?? (() => const <Message>[]);

  final String Function() conversationID;
  final bool Function() isClosed;
  final bool Function(Message) isRemoved;
  final ChatDateMessageSearch search;
  final FutureOr<void> Function(String, Message, DateTime) jumpToMessage;
  final void Function(String) showFeedback;
  final Future<Message?> Function(Future<Message?> Function()) runLoading;
  final List<Message> Function() _messages;
  bool _busy = false;
  int _revision = 0;

  // The SDK rejects searches with both empty keywords and empty types. Only
  // request types accepted by its post-pagination search filter.
  static const _messageTypes = [
    MessageType.text,
    MessageType.atText,
    MessageType.picture,
    MessageType.voice,
    MessageType.video,
    MessageType.file,
    MessageType.merger,
    MessageType.card,
    MessageType.location,
    MessageType.custom,
    MessageType.quote,
  ];

  /// Mirrors the anchor lookup, including real types unavailable to SDK search.
  bool hasLoadedMessagesOn(DateTime value) {
    if (isClosed()) return false;
    final day = DateTime(value.year, value.month, value.day);
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    return _latestOnDay(_messages(), day.millisecondsSinceEpoch,
            nextDay.millisecondsSinceEpoch) !=
        null;
  }

  Future<void> pickAndJump({
    required DateTime initialDate,
    required Future<DateTime?> Function(DateTime) pickDate,
  }) async {
    if (_busy || isClosed()) return;
    _busy = true;
    final revision = _revision;
    final id = conversationID();
    bool current() =>
        !isClosed() && revision == _revision && id == conversationID();
    try {
      final selected = await pickDate(initialDate.toLocal());
      if (selected == null || !current()) return;
      final day = DateTime(selected.year, selected.month, selected.day);
      final target = await runLoading(() => _findDay(id, day, current));
      if (!current()) return;
      if (target == null || isRemoved(target)) {
        showFeedback('chatDateHistoryEmpty'.tr);
      } else {
        await jumpToMessage(id, target, day);
      }
    } catch (_) {
      if (current()) showFeedback('chatDateHistoryFailed'.tr);
    } finally {
      // invalidate() may already have released this request and admitted a new
      // picker. Its delayed SDK result must not release the newer busy guard.
      if (revision == _revision) _busy = false;
    }
  }

  Future<Message?> _findDay(
      String id, DateTime day, bool Function() current) async {
    // Construct the next local midnight: a calendar day can be 23 or 25 hours.
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    final start = day.millisecondsSinceEpoch;
    final end = nextDay.millisecondsSinceEpoch;
    // Already loaded history can also anchor types unavailable to SDK search.
    final loaded = _latestOnDay(_messages(), start, end);
    if (loaded != null) return loaded;
    const pageSize = 20;
    for (var page = 1; current(); page++) {
      final result = await search(
        conversationID: id,
        messageTypeList: _messageTypes,
        searchTimePosition: end ~/ 1000,
        searchTimePeriod: (end - start) ~/ 1000,
        pageIndex: page,
        count: pageSize,
      );
      if (!current()) return null;
      final messages = result.searchResultItems
              ?.where((item) => item.conversationID == id)
              .expand((item) => item.messageList ?? <Message>[])
              .toList() ??
          <Message>[];
      // Native search includes both interval endpoints. Exclude the next day's
      // midnight while retaining every millisecond of the selected day.
      final candidate = _latestOnDay(messages, start, end);
      if (candidate != null) return candidate;
      // totalCount is the returned page count in this SDK, not the day's total.
      if (messages.length < pageSize) return null;
    }
    return null;
  }

  Message? _latestOnDay(Iterable<Message> messages, int start, int end) {
    Message? latest;
    for (final message in messages) {
      final time = message.sendTime;
      if (time == null ||
          time < start ||
          time >= end ||
          message.clientMsgID?.isNotEmpty != true ||
          isRemoved(message)) {
        continue;
      }
      if (latest == null ||
          time > latest.sendTime! ||
          (time == latest.sendTime && (message.seq ?? 0) > (latest.seq ?? 0))) {
        latest = message;
      }
    }
    return latest;
  }

  /// Conversation clear/close invalidates a picker or lookup already awaiting.
  void invalidate() {
    _revision++;
    _busy = false;
  }
}
