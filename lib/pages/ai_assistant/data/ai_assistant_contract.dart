import 'dart:convert';

class AiAssistantAnalyze {
  const AiAssistantAnalyze.c2c(this.peerUserId)
      : type = 'c2c',
        groupId = null,
        text = null;

  const AiAssistantAnalyze.group(this.groupId)
      : type = 'group',
        peerUserId = null,
        text = null;

  const AiAssistantAnalyze.paste(this.text)
      : type = 'paste',
        peerUserId = null,
        groupId = null;

  final String type;
  final String? peerUserId;
  final String? groupId;
  final String? text;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      if (peerUserId != null && peerUserId!.isNotEmpty)
        'peerUserId': peerUserId,
      if (groupId != null && groupId!.isNotEmpty) 'groupId': groupId,
      if (text != null) 'text': text,
    };
  }
}

class AiAssistantHistoryItem {
  const AiAssistantHistoryItem({
    required this.id,
    required this.role,
    required this.content,
    required this.capability,
    required this.analyzeType,
    required this.analyzePeerUserId,
    required this.analyzeGroupId,
    required this.status,
    required this.compressed,
    required this.sourceMessageCount,
    required this.createdAt,
    required this.imageUrl,
    required this.fileIds,
  });

  final String id;
  final String role;
  final String content;
  final String capability;
  final String analyzeType;
  final String analyzePeerUserId;
  final String analyzeGroupId;
  final String status;
  final bool compressed;
  final int sourceMessageCount;
  final int createdAt;
  final String imageUrl;
  final List<String> fileIds;

  factory AiAssistantHistoryItem.fromJson(Map<String, dynamic> json) {
    final files = json['fileIds'];
    return AiAssistantHistoryItem(
      id: _asString(json['id']),
      role: _asString(json['role']),
      content: json['content']?.toString() ?? '',
      capability: _asString(json['capability']),
      analyzeType: _asString(json['analyzeType']),
      analyzePeerUserId: _asString(json['analyzePeerUserId']),
      analyzeGroupId: _asString(json['analyzeGroupId']),
      status: _asString(json['status']),
      compressed: json['compressed'] == true,
      sourceMessageCount: _asInt(json['sourceMessageCount']),
      createdAt: _asInt(json['createdAt']),
      imageUrl: _asString(json['imageUrl']),
      fileIds: files is List
          ? files
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }
}

class AiAssistantHistoryPage {
  const AiAssistantHistoryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<AiAssistantHistoryItem> items;
  final bool hasMore;
  final String? nextCursor;

  factory AiAssistantHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map(
              (item) => AiAssistantHistoryItem.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
        : const <AiAssistantHistoryItem>[];
    final cursor = _asString(json['nextCursor']);
    return AiAssistantHistoryPage(
      items: items,
      hasMore: json['hasMore'] == true,
      nextCursor: cursor.isEmpty ? null : cursor,
    );
  }
}

class AiAssistantUploadedFile {
  const AiAssistantUploadedFile({
    required this.fileId,
    required this.contentType,
    required this.sizeBytes,
    required this.fileName,
  });

  final String fileId;
  final String contentType;
  final int sizeBytes;
  final String fileName;

  factory AiAssistantUploadedFile.fromJson(Map<String, dynamic> json) {
    return AiAssistantUploadedFile(
      fileId: _asString(json['fileId']),
      contentType: _asString(json['contentType']),
      sizeBytes: _asInt(json['sizeBytes']),
      fileName: _asString(json['fileName']),
    );
  }
}

enum AiAssistantStreamKind { meta, delta, done, error }

class AiAssistantStreamEvent {
  const AiAssistantStreamEvent({
    required this.kind,
    this.userMessageId,
    this.assistantMessageId,
    this.text = '',
    this.compressed = false,
    this.sourceMessageCount = 0,
    this.imageUrl = '',
    this.code = '',
    this.message = '',
  });

  final AiAssistantStreamKind kind;
  final String? userMessageId;
  final String? assistantMessageId;
  final String text;
  final bool compressed;
  final int sourceMessageCount;
  final String imageUrl;
  final String code;
  final String message;

  static AiAssistantStreamEvent? parse(String event, String data) {
    final trimmed = data.trim();
    if (trimmed.isEmpty || trimmed == '[DONE]') {
      return null;
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      json = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    switch (event) {
      case 'meta':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.meta,
          userMessageId: _nullableId(json['userMessageId']),
          assistantMessageId: _nullableId(json['assistantMessageId']),
        );
      case 'delta':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.delta,
          // Delta boundaries are transport boundaries, not word boundaries.
          text: json['text']?.toString() ?? '',
        );
      case 'done':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.done,
          assistantMessageId: _nullableId(json['assistantMessageId']),
          compressed: json['compressed'] == true,
          sourceMessageCount: _asInt(json['sourceMessageCount']),
          imageUrl: _asString(json['imageUrl']),
        );
      case 'error':
        return AiAssistantStreamEvent(
          kind: AiAssistantStreamKind.error,
          code: _asString(json['code']),
          message: _asString(json['message']),
        );
      default:
        return null;
    }
  }
}

String _asString(dynamic value) => value?.toString().trim() ?? '';

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _nullableId(dynamic value) {
  final text = _asString(value);
  return text.isEmpty ? null : text;
}
