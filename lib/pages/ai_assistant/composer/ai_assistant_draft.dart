import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';

enum AiAssistantDraftKind { card, file }

class AiAssistantDraftItem {
  const AiAssistantDraftItem.card(this.card)
      : kind = AiAssistantDraftKind.card,
        file = null;

  const AiAssistantDraftItem.file(this.file)
      : kind = AiAssistantDraftKind.file,
        card = null;

  final AiAssistantDraftKind kind;
  final AiAssistantCardRef? card;
  final AiAssistantFileRef? file;
}

class AiAssistantDraftFormats {
  AiAssistantDraftFormats._();

  static String bytes(int? value) {
    if (value == null || value <= 0) {
      return '--';
    }
    if (value < 1024) {
      return '$value B';
    }
    if (value < 1048576) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '${(value / 1048576).toStringAsFixed(1)} MB';
  }
}
