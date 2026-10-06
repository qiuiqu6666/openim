import 'package:openim/pages/ai_assistant/data/ai_assistant_api.dart';

import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';

class AiAssistantHistoryMap {
  AiAssistantHistoryMap._();

  static AiAssistantMessage toMessage(AiAssistantHistoryItem item) {
    final time = formatTime(item.createdAt);
    if (item.role == 'user') {
      return AiAssistantMessage(
        role: AiAssistantRole.user,
        time: time,
        text: item.content.isEmpty ? null : item.content,
        files: item.fileIds
            .map(
              (id) => AiAssistantFileRef(
                name: '附件',
                sizeLabel: '',
                kind: AiAssistantFileKind.unknown,
                fileId: id,
              ),
            )
            .toList(growable: false),
        cards: _cardsOf(item),
        serverId: item.id,
        capability: item.capability,
        status: item.status,
      );
    }
    if (item.status == 'streaming' &&
        item.content.isEmpty &&
        item.imageUrl.isEmpty) {
      return AiAssistantMessage(
        role: AiAssistantRole.assistant,
        time: '',
        outputKind: AiAssistantOutputKind.thinking,
        serverId: item.id,
        capability: item.capability,
        status: item.status,
      );
    }
    if (item.imageUrl.isNotEmpty) {
      return AiAssistantMessage(
        role: AiAssistantRole.assistant,
        time: time,
        outputKind: AiAssistantOutputKind.image,
        text: item.content.isEmpty ? null : item.content,
        imageUrl: item.imageUrl,
        serverId: item.id,
        capability: item.capability,
        status: item.status,
        failed: item.status == 'failed',
      );
    }
    return AiAssistantMessage(
      role: AiAssistantRole.assistant,
      time: time,
      outputKind: AiAssistantOutputKind.text,
      text: item.content,
      serverId: item.id,
      capability: item.capability,
      status: item.status,
      failed: item.status == 'failed',
    );
  }

  static List<AiAssistantCardRef> _cardsOf(AiAssistantHistoryItem item) {
    if (item.analyzeType == 'c2c' && item.analyzePeerUserId.isNotEmpty) {
      return <AiAssistantCardRef>[
        AiAssistantCardRef(
          kind: AiAssistantCardKind.friend,
          id: item.analyzePeerUserId,
          name: item.analyzePeerUserId,
        ),
      ];
    }
    if (item.analyzeType == 'group' && item.analyzeGroupId.isNotEmpty) {
      return <AiAssistantCardRef>[
        AiAssistantCardRef(
          kind: AiAssistantCardKind.group,
          id: item.analyzeGroupId,
          name: item.analyzeGroupId,
        ),
      ];
    }
    return const <AiAssistantCardRef>[];
  }

  static String formatTime(int ms) {
    if (ms <= 0) {
      return '';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
