import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../assistant_stream_chunk.dart';
import '../assistant_stream_state.dart';

/// Debug summaries only: no message text, account IDs, tokens or raw payloads.
abstract final class AssistantStreamLog {
  static const enabled =
      bool.fromEnvironment('AI_STREAM_DIAGNOSTICS', defaultValue: kDebugMode);
  static final _bubbleBuckets = Expando<Map<String, int>>();
  static final _seenStages = <String>{};

  static bool? _toCurrentUser(Message message) {
    // Native callbacks can precede login; diagnostics must not break delivery.
    try {
      return message.recvID == OpenIM.iMManager.userID;
    } catch (_) {
      return null;
    }
  }

  static Map? _data(Message message) {
    try {
      final data = jsonDecode(message.customElem?.data ?? '');
      return data is Map ? data : null;
    } on FormatException {
      return null;
    }
  }

  static String? _stream(Object? value) =>
      value is String ? value.hashCode.toUnsigned(32).toRadixString(16) : null;

  static bool _sample(int? index, bool end) =>
      index == null || index == 0 || end || index % 10 == 0;

  static bool _firstOrSample(String stage, Map? data) {
    final stream = _stream(data?['streamID']);
    if (stream == null) return true;
    final key = '$stage:$stream';
    if (!_seenStages.contains(key)) {
      if (_seenStages.length >= 128) _seenStages.remove(_seenStages.first);
      _seenStages.add(key);
      return true;
    }
    return _sample(data?['index'] is int ? data!['index'] as int : null,
        data?['end'] == true);
  }

  static Map<String, Object?> _fields(Message message, Map? data) => {
        'type': message.contentType,
        'singleChat': message.isSingleChat,
        'fromAssistant': message.sendID == 'assistant',
        'toCurrentUser': _toCurrentUser(message),
        'streamEnvelope': AssistantStreamChunk.isStreamMessage(message),
        'matchesDescription':
            message.customElem?.description == AssistantStreamChunk.description,
        'validObject': data != null,
        'stream': _stream(data?['streamID']),
        'indexPresent': data?.containsKey('index') ?? false,
        'indexType': '${data?['index'].runtimeType}',
        if (data?['index'] is int) 'index': data!['index'],
        'endPresent': data?.containsKey('end') ?? false,
        'endType': '${data?['end'].runtimeType}',
        if (data?['end'] is bool) 'end': data!['end'],
        'textType': '${data?['text'].runtimeType}',
        if (data?['text'] is String)
          'textUnits': (data!['text'] as String).length,
      };

  static void _write(String stage, Map<String, Object?> fields) {
    if (!enabled) return;
    debugPrint('[AI流式][$stage] ${jsonEncode({
          'at': DateTime.now().toIso8601String(),
          ...fields,
        })}');
  }

  static void received(Message message,
      {required String source, required bool hasReceiver}) {
    if (!enabled ||
        (message.sendID != 'assistant' &&
            !AssistantStreamChunk.isStreamMessage(message))) {
      return;
    }
    final data = _data(message);
    if (!_firstOrSample('receive:$source', data)) return;
    _write('receive', {
      'source': source,
      'hasReceiver': hasReceiver,
      ..._fields(message, data),
    });
  }

  static void routed(Message message,
      {required bool active,
      required bool currentChat,
      required bool assistantChat,
      required bool buffering}) {
    if (!enabled || !AssistantStreamChunk.isStreamMessage(message)) {
      return;
    }
    final data = _data(message);
    if (!_firstOrSample('route', data)) return;
    _write('route', {
      'active': active,
      'currentChat': currentChat,
      'assistantChat': assistantChat,
      'buffering': buffering,
      ..._fields(message, data),
    });
  }

  static void invalid(Message message) {
    if (enabled) _write('invalid', _fields(message, _data(message)));
  }

  static void accepted(
      AssistantStreamChunk chunk, AssistantStreamSnapshot? snapshot,
      {required bool buffering, required bool finalized}) {
    if (!enabled || !_sample(chunk.index, chunk.end)) return;
    _write('accept', {
      'stream': _stream(chunk.streamID),
      'index': chunk.index,
      'end': chunk.end,
      'changed': snapshot != null,
      'finalized': finalized,
      'textUnits': chunk.text.length,
      'visibleUnits': snapshot?.text.length,
      'buffering': buffering,
    });
  }

  static void finalReply(Message message) {
    if (!enabled ||
        message.sendID != 'assistant' ||
        !message.isSingleChat ||
        message.contentType != MessageType.text) {
      return;
    }
    _write('final', {
      'stream': _stream(AssistantStreamChunk.finalStreamID(message)),
      'textUnits': message.textElem?.content?.length,
      'toCurrentUser': _toCurrentUser(message),
    });
  }

  static void bubble(
      AssistantStreamState owner, AssistantStreamSnapshot reply) {
    if (!enabled) return;
    final buckets = _bubbleBuckets[owner] ??= <String, int>{};
    final bucket = reply.ended ? -1 : reply.text.length ~/ 256;
    if (buckets[reply.streamID] == bucket) return;
    if (buckets.length >= 64 && !buckets.containsKey(reply.streamID)) {
      buckets.remove(buckets.keys.first);
    }
    buckets[reply.streamID] = bucket;
    _write('bubble_build', {
      'stream': _stream(reply.streamID),
      'visibleUnits': reply.text.length,
      'ended': reply.ended,
    });
  }

  static void submitted(int textUnits) =>
      _write('submit', {'textUnits': textUnits});
}
