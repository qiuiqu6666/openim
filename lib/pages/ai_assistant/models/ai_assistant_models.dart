import 'dart:typed_data';

enum AiAssistantFileKind {
  pdf,
  word,
  excel,
  ppt,
  image,
  video,
  audio,
  text,
  archive,
  unknown,
}

enum AiAssistantRole { user, assistant }

enum AiAssistantOutputKind {
  thinking,
  text,
  summary,
  image,
  fileAnalysis,
  code,
}

enum AiAssistantCardKind { friend, group }

class AiAssistantCardRef {
  const AiAssistantCardRef({
    required this.kind,
    required this.id,
    required this.name,
    this.faceUrl = '',
  });

  final AiAssistantCardKind kind;
  final String id;
  final String name;
  final String faceUrl;
}

class AiAssistantFileRef {
  const AiAssistantFileRef({
    required this.name,
    required this.sizeLabel,
    required this.kind,
    this.localPath,
    this.fileId,
    this.bytes,
    this.mimeType,
    this.sizeBytes,
  });

  final String name;
  final String sizeLabel;
  final AiAssistantFileKind kind;
  final String? localPath;
  final String? fileId;
  final Uint8List? bytes;
  final String? mimeType;
  final int? sizeBytes;
}

class AiAssistantSummaryData {
  const AiAssistantSummaryData({
    required this.title,
    required this.meta,
    required this.items,
    required this.footer,
  });

  final String title;
  final String meta;
  final List<String> items;
  final String footer;
}

class AiAssistantAnalysisData {
  const AiAssistantAnalysisData({
    required this.fileName,
    required this.sizeLabel,
    required this.bullets,
  });

  final String fileName;
  final String sizeLabel;
  final List<String> bullets;
}

class AiAssistantCodeData {
  const AiAssistantCodeData({
    required this.language,
    required this.source,
  });

  final String language;
  final String source;
}

class AiAssistantMessage {
  const AiAssistantMessage({
    required this.role,
    required this.time,
    this.text,
    this.files = const <AiAssistantFileRef>[],
    this.cards = const <AiAssistantCardRef>[],
    this.outputKind,
    this.summary,
    this.analysis,
    this.code,
    this.serverId,
    this.capability,
    this.status,
    this.imageUrl,
    this.failed = false,
  });

  final AiAssistantRole role;
  final String time;
  final String? text;
  final List<AiAssistantFileRef> files;
  final List<AiAssistantCardRef> cards;
  final AiAssistantOutputKind? outputKind;
  final AiAssistantSummaryData? summary;
  final AiAssistantAnalysisData? analysis;
  final AiAssistantCodeData? code;
  final String? serverId;
  final String? capability;
  final String? status;
  final String? imageUrl;
  final bool failed;
}
