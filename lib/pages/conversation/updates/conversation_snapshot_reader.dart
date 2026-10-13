import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../../core/session/queries/sdk_query_gate.dart';

/// Read a bounded snapshot while retaining the real native request's slot.
class ConversationSnapshotReader {
  ConversationSnapshotReader(
      {this.pageSize = 400, this.timeout = const Duration(seconds: 30)});
  final int pageSize;
  final Duration timeout;
  final _reads = SdkQueryGate<List<ConversationInfo>>();

  Future<List<ConversationInfo>> read(
      {required bool firstPageOnly,
      required bool Function() isCurrent,
      required int Function() structureRevision,
      required void Function(List<ConversationInfo>) observePage,
      Future<void>? waitForMutation}) async {
    final elapsed = Stopwatch()..start();
    Duration remaining() {
      final budget = timeout - elapsed.elapsed;
      if (budget <= Duration.zero)
        throw TimeoutException('Conversation snapshot timed out', timeout);
      return budget;
    }

    if (waitForMutation != null) {
      try {
        await waitForMutation.timeout(remaining());
      } on TimeoutException {
        rethrow;
      } catch (_) {
        // The cleanup owner reports its own failure; a finished mutation
        // must not prevent the authoritative local snapshot from loading.
      }
    }
    for (var pass = 0; pass < 2; ++pass) {
      final revision = structureRevision();
      final rows = <String, ConversationInfo>{};
      var offset = 0;
      while (isCurrent()) {
        final page = await _reads.run(
            Object(),
            () => OpenIM.iMManager.conversationManager
                .getConversationListSplit(offset: offset, count: pageSize),
            timeout: remaining(),
            isCurrent: isCurrent);
        observePage(page);
        if (!firstPageOnly && revision != structureRevision()) break;
        final previousSize = rows.length;
        for (final row in page) {
          rows[row.conversationID] = row;
        }
        if (firstPageOnly || page.length < pageSize)
          return rows.values.toList();
        if (rows.length == previousSize) {
          throw StateError('Conversation pagination did not advance');
        }
        offset += page.length;
      }
      if (!isCurrent()) throw StateError('Conversation snapshot owner changed');
    }
    throw StateError('Conversation order changed during snapshot; retry later');
  }

  void close() => _reads.close();
}
