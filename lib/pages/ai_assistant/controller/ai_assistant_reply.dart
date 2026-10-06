import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/ai_assistant_models.dart';

/// A streaming turn owns its cancellation, buffered text and row notifier.
class AiAssistantReply {
  AiAssistantReply(this.user, AiAssistantMessage assistant,
      {bool Function()? isCurrent})
      : _isCurrent = isCurrent ?? (() => true),
        visible = ValueNotifier(assistant);
  final bool Function() _isCurrent;
  AiAssistantMessage user;
  final ValueNotifier<AiAssistantMessage> visible;
  final token = CancelToken();
  final text = StringBuffer();
  Timer? _publication;
  bool terminal = false;

  void append(String delta) {
    if (terminal || !_isCurrent()) return;
    text.write(delta);
    _publication ??= Timer(const Duration(milliseconds: 32), publish);
  }

  void publish() {
    _publication?.cancel();
    _publication = null;
    if (terminal || !_isCurrent() || text.isEmpty) return;
    visible.value = copyAiMessage(visible.value,
        text: text.toString(), outputKind: AiAssistantOutputKind.text);
  }

  void finish(AiAssistantMessage message) {
    if (terminal) return;
    _publication?.cancel();
    _publication = null;
    visible.value = message;
    terminal = true;
    token.cancel('terminal');
  }

  void dispose() {
    terminal = true;
    _publication?.cancel();
    token.cancel('dispose');
    visible.dispose();
  }
}

AiAssistantMessage copyAiMessage(AiAssistantMessage message,
        {String? text,
        String? time,
        String? status,
        String? serverId,
        String? imageUrl,
        bool? failed,
        AiAssistantOutputKind? outputKind,
        List<AiAssistantFileRef>? files}) =>
    AiAssistantMessage(
      role: message.role,
      time: time ?? message.time,
      text: text ?? message.text,
      files: files ?? message.files,
      cards: message.cards,
      outputKind: outputKind ?? message.outputKind,
      summary: message.summary,
      analysis: message.analysis,
      code: message.code,
      serverId: serverId ?? message.serverId,
      capability: message.capability,
      status: status ?? message.status,
      imageUrl: imageUrl ?? message.imageUrl,
      failed: failed ?? message.failed,
    );
