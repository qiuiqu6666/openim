import 'dart:convert';

/// Payloads understood by the assistant inside its normal OpenIM conversation.
class AiOpenimPayload {
  const AiOpenimPayload._();

  static const maxDocumentBytes = 20 * 1024 * 1024;
  static const documentExtensions = ['pdf', 'docx', 'txt'];

  static bool acceptsDocument(String name, int size) {
    final dot = name.lastIndexOf('.');
    return dot > 0 &&
        size >= 0 &&
        size <= maxDocumentBytes &&
        documentExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// Empty prompts are valid protocol input; the assistant supplies guidance.
  static String image(String prompt) => jsonEncode({'prompt': prompt.trim()});

  static String groupCard({
    required String groupID,
    required String groupName,
    required String faceURL,
  }) =>
      jsonEncode({
        'groupID': groupID,
        'groupName': groupName,
        'faceURL': faceURL,
      });
}
