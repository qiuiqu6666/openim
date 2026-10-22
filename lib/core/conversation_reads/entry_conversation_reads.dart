import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'conversation_batch_read_api.dart';
import 'read_watermark_queue.dart';

/// Owns read intentions beyond the chat route; native receipts still own DB
/// message flags and OS aggregate badges. No full-conversation retry is used.
class EntryConversationReads {
  EntryConversationReads(
      {required bool Function() isCurrent,
      required void Function() changed,
      required void Function(List<String>) acknowledged}) {
    _isCurrent = () => !_closed && isCurrent() && _api.isCurrent;
    final key = 'entry_read_watermarks_v1_${jsonEncode([
          Config.imApiUrl,
          OpenIM.iMManager.userID
        ])}';
    Map data = {};
    try {
      data = SpUtil().getObject(key) ?? {};
    } catch (e) {
      _error(e);
    }
    Map<String, int> decode(Object? value) => value is Map
        ? {
            for (final e in value.entries)
              if (e.key is String && e.value is int && e.value > 0)
                e.key as String: e.value as int
          }
        : {};
    queue = ReadWatermarkQueue(
      targets: decode(data['targets']),
      confirmed: decode(data['confirmed']),
      save: (targets, confirmed) async {
        final saved = await SpUtil()
            .putObject(key, {'targets': targets, 'confirmed': confirmed});
        if (saved != true) throw StateError('Could not persist read cutoff');
      },
      apply: _api.apply,
      isCurrent: _isCurrent,
      changed: changed,
      acknowledged: acknowledged,
      onError: _error,
    );
  }

  final _api = ConversationBatchReadApi();
  late final bool Function() _isCurrent;
  bool _closed = false;
  late final ReadWatermarkQueue queue;
  static void _error(Object error) =>
      Logger.print('Entry read pending: ${error.runtimeType}');

  Future<void> enqueue(BatchReadTarget target) async {
    try {
      await queue.enqueue(target);
    } catch (e) {
      _error(e);
    }
  }

  ConversationInfo project(ConversationInfo info, {ConversationInfo? current}) {
    if (!_isCurrent()) return info;
    final seq = info.latestMsg?.seq ?? 0;
    final through = queue.through(info.conversationID);
    if (through <= 0 ||
        seq <= 0 ||
        info.isPrivateChat == true ||
        info.latestMsg?.attachedInfoElem?.isPrivateChat == true ||
        info.latestMsg?.status != MessageStatus.succeeded) {
      return info;
    }
    // An old read callback must not replace a newer preview/unread row.
    if (current != null &&
        current.conversationID == info.conversationID &&
        seq <= through &&
        (current.latestMsg?.seq ?? 0) > seq) {
      return project(current);
    }
    // Sequence distance is only an upper bound, never a reconstructed count.
    // min preserves an authoritative smaller count (own/system messages/gaps).
    final remaining = (seq - through).clamp(0, info.unreadCount);
    if (remaining == info.unreadCount) return info;
    return ConversationInfo.fromJson(info.toJson())..unreadCount = remaining;
  }

  void close() {
    _closed = true;
    queue.close();
    _api.close();
  }
}
