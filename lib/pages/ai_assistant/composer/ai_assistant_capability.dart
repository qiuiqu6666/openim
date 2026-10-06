import '../data/ai_assistant_api.dart';
import '../data/ai_assistant_upload_mime.dart';
import '../models/ai_assistant_models.dart';

class AiAssistantSendError {
  const AiAssistantSendError({required this.zhHans, required this.en,
    this.zhHant = '', this.ja = '', this.ko = ''});
  final String zhHans, zhHant, en, ja, ko;
  String localize({String languageCode = 'zh'}) {
    if (languageCode.startsWith('zh')) return languageCode.contains('Hant') && zhHant.isNotEmpty ? zhHant : zhHans;
    if (languageCode == 'ja' && ja.isNotEmpty) return ja;
    if (languageCode == 'ko' && ko.isNotEmpty) return ko;
    return en;
  }
}

class AiAssistantSendPlan {
  const AiAssistantSendPlan({required this.capability, required this.content,
    required this.displayText, this.analyze,
    this.files = const <AiAssistantFileRef>[], this.cards = const <AiAssistantCardRef>[]});
  final String capability, content, displayText;
  final AiAssistantAnalyze? analyze;
  final List<AiAssistantFileRef> files;
  final List<AiAssistantCardRef> cards;
}

/// Converts composer state into the reference contract without creating replies.
class AiAssistantSendPlanner {
  AiAssistantSendPlanner._();
  static const chat = 'chat', summarize = 'summarize', copy = 'copy', file = 'file', image = 'image';

  static String fromTool(String? tool) => switch (tool) {
    'summarize' => summarize, 'write' => copy, 'analyze' => file, 'image' => image, _ => chat,
  };

  static String resolveCapability({required String? tool, required bool hasCards,
    required List<AiAssistantFileRef> files}) {
    if (tool == 'write') return copy;
    if (tool == 'summarize' || (hasCards && tool != 'image' && tool != 'analyze')) return summarize;
    if (tool == 'image') return image;
    if (tool == 'analyze' || files.any((f) => AiAssistantUploadMime.isPdf(f.name, f.mimeType))) return file;
    return fromTool(tool);
  }

  static AiAssistantSendError _error(String zh, String en) => AiAssistantSendError(zhHans: zh, en: en);

  static Object plan({required String? tool, required String text,
    required List<AiAssistantCardRef> cards, required List<AiAssistantFileRef> files}) {
    final content = text.trim();
    if (content.runes.length > AiAssistantUploadMime.maxContentChars) return _error('内容最多8000字', 'Message can be at most 8000 characters.');
    final capability = resolveCapability(tool: tool, hasCards: cards.isNotEmpty, files: files);
    if (capability == summarize) {
      if (files.isNotEmpty) return _error('总结聊天记录不能附带文件', 'Summarize cannot include files.');
      if (cards.length != 1) return _error('请先选择一个对话或群聊', 'Pick one chat or group first.');
      final card = cards.single;
      if (card.id.trim().isEmpty) return _error('所选对话不可用', 'The selected chat is unavailable.');
      return AiAssistantSendPlan(capability: summarize, content: content,
        displayText: content.isEmpty ? '[分析聊天记录]' : content,
        analyze: card.kind == AiAssistantCardKind.group ? AiAssistantAnalyze.group(card.id) : AiAssistantAnalyze.c2c(card.id),
        cards: List.unmodifiable(cards));
    }
    if (cards.isNotEmpty) return _error('该功能不能附带名片', 'This tool cannot include contact cards.');
    if (capability == copy) {
      if (files.isNotEmpty) return _error('写文案只需文字', 'Copywriting only needs text.');
      if (content.isEmpty) return _error('请输入文案主题或要求', 'Enter the topic or requirements.');
    } else {
      if (files.length > AiAssistantUploadMime.maxFileCount) return _error('一次最多3个附件', 'You can attach up to 3 files.');
      if (capability == file && files.isEmpty) return _error('请添加要分析的文件', 'Add a file to analyze.');
      final error = capability == image ? validateImageFiles(files) : capability == file ? validateFiles(files) : validateChatFiles(files);
      if (error != null) return error;
      final duplicate = validateNoDuplicateFiles(files);
      if (duplicate != null) return duplicate;
      if ((capability == chat || capability == image) && content.isEmpty) {
        return capability == image ? _error('请描述你想生成的图片', 'Describe the image you want.') : _error('请输入文字或添加附件', 'Type a message or add an attachment.');
      }
    }
    return AiAssistantSendPlan(capability: capability, content: content,
      displayText: content.isEmpty ? '[分析文件]' : content, files: List.unmodifiable(files));
  }

  static AiAssistantSendError? validateImageFiles(List<AiAssistantFileRef> files) =>
      _validate(files, (f) => AiAssistantUploadMime.isAllowedImage(f.name, f.mimeType),
          '改图仅支持JPG / PNG / WEBP / GIF', 'Image edits only allow JPG, PNG, WEBP, or GIF.');
  static AiAssistantSendError? validateChatFiles(List<AiAssistantFileRef> files) =>
      _validate(files, (f) => AiAssistantUploadMime.isChatAttachment(f.name, f.mimeType),
          '闲聊仅支持图片、表格或视频', 'Chat attachments must be images, spreadsheets, or videos.');
  static AiAssistantSendError? validateFiles(List<AiAssistantFileRef> files) =>
      _validate(files, (f) => AiAssistantUploadMime.matchesMime(f.name, f.mimeType) &&
          AiAssistantUploadMime.allowedMimes.contains(AiAssistantUploadMime.fromName(f.name)),
          '仅支持图片、表格、视频或PDF', 'Only images, spreadsheets, videos, or PDF are allowed.');
  static AiAssistantSendError? _validate(List<AiAssistantFileRef> files,
    bool Function(AiAssistantFileRef) allowed, String zh, String en) {
    for (final item in files) {
      if (!allowed(item)) return _error(zh, en);
      if (item.sizeBytes != null && item.sizeBytes! > AiAssistantUploadMime.maxBytes) return _error('文件不能超过20MB', 'Each file must be 20MB or smaller.');
    }
    return null;
  }
  static AiAssistantSendError? validateNoDuplicateFiles(List<AiAssistantFileRef> files) {
    final seen = <String>{};
    for (final item in files) {
      final id = item.fileId?.trim() ?? '', path = item.localPath?.trim() ?? '';
      final key = id.isNotEmpty ? 'id:$id' : path.isNotEmpty ? 'path:$path' : 'name:${item.name}|${item.sizeBytes ?? ''}';
      if (!seen.add(key)) return _error('不能添加重复文件', 'Duplicate files are not allowed.');
    }
    return null;
  }
}

class AiAssistantErrorText {
  AiAssistantErrorText._();
  static String localize({String languageCode = 'zh', required String code, String fallback = ''}) {
    final zh = languageCode.startsWith('zh');
    return switch (code) {
      'SERVICE_UNAVAILABLE' => zh ? '当前服务器尚未接入AI助手服务' : 'AI assistant is not connected to this server yet.',
      'UNAUTHORIZED' || 'SESSION_CHANGED' => zh ? '登录已失效，请重新登录' : 'Session expired. Please sign in again.',
      'CHAT_BUSY' => zh ? '上一条回复还在生成中' : 'A reply is still generating.',
      'INCOMPLETE_STREAM' => zh ? '回复中断，请查看历史记录后重试' : 'Reply interrupted. Check history before retrying.',
      'FILE_TOO_LARGE' => zh ? '文件不能超过20MB' : 'File is larger than 20MB.',
      'FILE_UNAVAILABLE' => zh ? '文件不可用' : 'File is unavailable.',
      'NOT_FRIEND' => zh ? '对方还不是好友，无法总结该对话' : 'You can only summarize a mutual friend chat.',
      'NOT_GROUP_MEMBER' => zh ? '你不在该群，无法总结' : 'You are not in that group.',
      'ARCHIVE_RATE_LIMITED' => zh ? '请求过于频繁，请稍后再试' : 'Too many requests. Try again later.',
      'LLM_NOT_CONFIGURED' || 'LLM_UPSTREAM' || 'MAIN_UNAVAILABLE' => zh ? '助手暂时不可用，请稍后重试' : 'The assistant is unavailable. Try again later.',
      _ => fallback.isNotEmpty ? fallback : zh ? '请求失败，请稍后重试' : 'Request failed. Try again later.',
    };
  }
}
