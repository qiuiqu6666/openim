import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// An online-only delta. The ordinary final SDK message remains authoritative.
class AssistantStreamChunk {
  const AssistantStreamChunk({
    required this.streamID,
    required this.index,
    required this.text,
    required this.end,
  });

  static const description = 'assistantStream';
  final String streamID;
  final int index;
  final String text;
  final bool end;

  /// Identify the transport envelope even when its payload is malformed.
  static bool isStreamMessage(Message message) =>
      message.contentType == MessageType.custom &&
      message.customElem?.description == description;

  static AssistantStreamChunk? tryParse(Message message) {
    if (!isStreamMessage(message)) return null;
    try {
      final data = jsonDecode(message.customElem?.data ?? '');
      if (data is! Map ||
          data['streamID'] is! String ||
          (data['streamID'] as String).trim().isEmpty ||
          data['index'] is! int ||
          (data['index'] as int) < 0 ||
          data['text'] is! String ||
          data['end'] is! bool) {
        return null;
      }
      return AssistantStreamChunk(
        streamID: data['streamID'],
        index: data['index'],
        text: data['text'],
        end: data['end'],
      );
    } on FormatException {
      return null;
    }
  }

  static String? finalStreamID(Message message) {
    if (message.contentType != MessageType.text) return null;
    try {
      final ex = jsonDecode(message.ex ?? '');
      final id = ex is Map ? ex['streamID'] : null;
      return id is String && id.trim().isNotEmpty ? id : null;
    } on FormatException {
      return null;
    }
  }
}
