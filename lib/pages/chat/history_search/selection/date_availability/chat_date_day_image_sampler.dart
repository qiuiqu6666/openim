import 'dart:math';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../chat_history_search_source.dart';
import 'chat_date_day_image.dart';

/// Samples one bounded SDK page inside the availability owner's request slot.
/// It owns no listeners, cache, timer, queue or media downloads.
class ChatDateDayImageSampler {
  ChatDateDayImageSampler({
    required this.source,
    required this.isRemoved,
    int Function(int length)? chooseIndex,
  }) : _chooseIndex = chooseIndex ?? Random().nextInt;

  static const sampleSize = 20;
  final ChatHistorySearchSource source;
  final bool Function(Message message) isRemoved;
  final int Function(int length) _chooseIndex;

  Future<Message?> sample({
    required String conversationID,
    required DateTime day,
    required bool Function() isCurrent,
    Message? preferred,
  }) async {
    final query = ChatHistorySearchQuery(
      startDate: day,
      endDate: day,
      messageTypes: const [MessageType.picture],
    ).snapshot();
    final nextMidnight = query.localEndExclusive!.millisecondsSinceEpoch;
    final seenBoundaryPages = <String>{};
    try {
      for (var pageIndex = 1; isCurrent(); pageIndex++) {
        final messages = await source.search(
          conversationID: conversationID,
          query: query,
          pageIndex: pageIndex,
          count: sampleSize,
        );
        if (!isCurrent()) return null;
        final candidates = messages
            .where((message) =>
                ChatDateDayImage.fromMessage(message,
                    day: day, isRemoved: isRemoved) !=
                null)
            .take(sampleSize)
            .toList(growable: false);
        if (candidates.isNotEmpty) {
          final preferredID = preferred?.clientMsgID;
          if (preferredID?.isNotEmpty == true) {
            for (final candidate in candidates) {
              if (candidate.clientMsgID == preferredID) return candidate;
            }
          }
          return candidates[_chooseIndex(candidates.length)];
        }
        // The native upper bound is inclusive. Only skip a full adjacent-day
        // midnight page; do not scan thousands of private/invalid day photos.
        if (messages.length < sampleSize ||
            messages.any((message) => message.sendTime != nextMidnight)) {
          return null;
        }
        final fingerprint = messages
            .map((message) =>
                '${message.clientMsgID}|${message.sendTime}|${message.seq}')
            .join('\n');
        if (!seenBoundaryPages.add(fingerprint)) return null;
      }
    } catch (_) {
      // A missing photo is cosmetic; the already confirmed date stays usable.
    }
    return null;
  }
}
