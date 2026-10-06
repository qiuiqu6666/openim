import 'dart:convert';

/// Reads SDK plain drafts and the composer's text/mentions envelope.
/// The stored draft and its mention metadata remain unchanged.
String? conversationDraftText(String? draft) {
  if (draft == null || draft.isEmpty) return null;
  var text = draft;
  try {
    final value = jsonDecode(draft);
    if (value is Map && value['text'] is String) text = value['text'];
  } catch (_) {
    // Legacy and user-authored drafts may be plain text.
  }
  return text.isEmpty ? null : text;
}
