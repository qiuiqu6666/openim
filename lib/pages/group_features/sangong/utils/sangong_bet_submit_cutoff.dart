// Adapted from 99chat d7c3c65; OpenIM identifiers and message metadata adapted.
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// 截止下注边界参数（优先级：untilMessageId > untilMsgSeq > 默认最新消息）。
class SangongBetSubmitCutoff {
  const SangongBetSubmitCutoff({
    this.untilMessageId,
    this.untilMsgSeq,
    this.excludeMessageId,
    this.excludeMessageIds = const [],
  });

  final int? untilMessageId;
  final int? untilMsgSeq;
  final int? excludeMessageId;
  final List<int> excludeMessageIds;

  bool get hasExplicitBoundary => untilMessageId != null || untilMsgSeq != null;

  bool get hasExclusions => allExcludeMessageIds.isNotEmpty;

  List<int> get allExcludeMessageIds {
    final ids = <int>{};
    if (excludeMessageId != null && excludeMessageId! > 0) {
      ids.add(excludeMessageId!);
    }
    for (final id in excludeMessageIds) {
      if (id > 0) {
        ids.add(id);
      }
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }

  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{};
    if (untilMessageId != null) {
      body['untilMessageId'] = untilMessageId;
    } else if (untilMsgSeq != null) {
      body['untilMsgSeq'] = untilMsgSeq;
    }

    final excludes = allExcludeMessageIds;
    if (excludes.length == 1) {
      body['excludeMessageId'] = excludes.single;
    } else if (excludes.length > 1) {
      body['excludeMessageIds'] = excludes;
    }
    return body;
  }

  /// 追加排除一条 IM 消息 id（去重、升序）。
  SangongBetSubmitCutoff withAdditionalExclude(int messageId) {
    if (messageId <= 0) {
      return this;
    }
    final ids = <int>{...allExcludeMessageIds, messageId}.toList()..sort();
    if (ids.length == 1) {
      return SangongBetSubmitCutoff(
        untilMessageId: untilMessageId,
        untilMsgSeq: untilMsgSeq,
        excludeMessageId: ids.single,
      );
    }
    return SangongBetSubmitCutoff(
      untilMessageId: untilMessageId,
      untilMsgSeq: untilMsgSeq,
      excludeMessageIds: ids,
    );
  }

  /// 长按消息气泡截止：优先 IM 消息 id，其次 MsgSeq。
  static SangongBetSubmitCutoff? fromLongPressedMessage(Message message) {
    final messageId = readBackendMessageId(message);
    if (messageId != null) {
      return SangongBetSubmitCutoff(untilMessageId: messageId);
    }
    final msgSeq = readMessageSeq(message);
    if (msgSeq != null) {
      return SangongBetSubmitCutoff(untilMsgSeq: msgSeq);
    }
    return null;
  }

  /// 长按「不计入」：排除指定 IM 消息 id（须在截止范围内）。
  static SangongBetSubmitCutoff? excludingMessage(Message message) {
    final messageId = readBackendMessageId(message);
    if (messageId == null) {
      return null;
    }
    return SangongBetSubmitCutoff(excludeMessageId: messageId);
  }

  static bool canExcludeMessage(Message message) {
    return readBackendMessageId(message) != null;
  }

  /// 从云端/本地自定义字段解析后端 IM 消息 id。
  static int? readBackendMessageId(Message message) {
    for (final raw in [message.ex]) {
      final id = _messageIdFromCustomPayload(raw);
      if (id != null) {
        return id;
      }
    }
    return null;
  }

  static int? readMessageSeq(Message message) {
    return _readPositiveInt(message.seq);
  }

  static String? readMessagePreviewText(Message message) {
    if (message.contentType == MessageType.text) {
      final text = message.textElem?.content?.trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static String readSenderLabel(Message message) {
    for (final value in [
      message.senderNickname,
      message.sendID,
    ]) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  static int? _messageIdFromCustomPayload(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        for (final key in const [
          'messageId',
          'message_id',
          'imMessageId',
          'im_message_id',
          'sgMessageId',
          'sg_message_id',
        ]) {
          final id = _readPositiveInt(map[key]);
          if (id != null) {
            return id;
          }
        }
      }
    } catch (_) {}
    return _readPositiveInt(trimmed);
  }

  static int? _readPositiveInt(Object? raw) {
    if (raw is int) {
      return raw > 0 ? raw : null;
    }
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value : null;
    }
    return int.tryParse(raw?.toString() ?? '');
  }
}
