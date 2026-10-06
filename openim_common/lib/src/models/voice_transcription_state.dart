import 'package:flutter/foundation.dart';

/// Local transcription and presentation state for one voice message.
@immutable
class VoiceTranscriptionState {
  const VoiceTranscriptionState({
    this.text,
    this.loading = false,
    this.error,
    this.expanded = true,
  });

  final String? text;
  final bool loading;
  final String? error;
  final bool expanded;

  bool get hasText => text?.trim().isNotEmpty == true;
  bool get isLoading => loading;
}
