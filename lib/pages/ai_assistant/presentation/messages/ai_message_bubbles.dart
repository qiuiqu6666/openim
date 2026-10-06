import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../theme/ai_palette.dart';
import '../../localization/ai_assistant_i18n.dart';
import '../../models/ai_assistant_models.dart';
import 'ai_assistant_text.dart';
import 'ai_attachment_rows.dart';
import 'ai_output_cards.dart';

class AiUserBubble extends StatelessWidget {
  const AiUserBubble({
    super.key,
    required this.dark,
    required this.message,
    required this.faceUrl,
    required this.showName,
    required this.ownerId,
    required this.onCardTap,
    required this.onFileTap,
    required this.fileCache,
    this.query = '',
    this.onLongPress,
  });

  final bool dark;
  final AiAssistantMessage message;
  final String faceUrl;
  final String showName;
  final String ownerId;
  final ValueChanged<AiAssistantCardRef> onCardTap;
  final ValueChanged<AiAssistantFileRef> onFileTap;
  final Map<String, Uint8List> fileCache;
  final String query;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final maxWidth =
        MediaQuery.sizeOf(context).width * AiMetrics.bubbleWidthRatio;
    final text = message.text?.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        GestureDetector(
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (text.isNotEmpty)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AiPalette.bubble(dark),
                      borderRadius: BorderRadius.circular(AiMetrics.radius16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AiMetrics.space12,
                        vertical: AiMetrics.space10,
                      ),
                      child: AiHighlightText(
                        text: text,
                        query: query,
                        style: const TextStyle(
                          color: AiPalette.onAccent,
                          fontSize: AiMetrics.font15,
                          height: AiMetrics.userTextLineHeight,
                        ),
                      ),
                    ),
                  ),
                for (final card in message.cards) ...[
                  const SizedBox(height: AiMetrics.dimension8),
                  AiUserCardRow(
                    dark: dark,
                    card: card,
                    onTap: () => onCardTap(card),
                    query: query,
                  ),
                ],
                for (final file in message.files) ...[
                  const SizedBox(height: AiMetrics.dimension8),
                  if (aiCanShowUserImage(file, fileCache))
                    AiUserImageThumb(
                      dark: dark,
                      file: file,
                      bytes:
                          file.bytes ?? fileCache[(file.fileId ?? '').trim()],
                      onTap: () => onFileTap(file),
                      query: query,
                    )
                  else
                    AiUserFileRow(
                      dark: dark,
                      file: file,
                      onTap: () => onFileTap(file),
                      query: query,
                    ),
                ],
                const SizedBox(height: AiMetrics.dimension4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.time,
                      style: TextStyle(
                        color: AiPalette.secondary(dark),
                        fontSize: AiMetrics.font11,
                      ),
                    ),
                    const SizedBox(width: AiMetrics.dimension2),
                    Icon(
                      Icons.done,
                      size: AiMetrics.dimension14,
                      color: AiPalette.secondary(dark),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AiMetrics.dimension8),
        AvatarView(
          url: faceUrl,
          text: showName,
          width: AiMetrics.dimension32,
          height: AiMetrics.dimension32,
        ),
      ],
    );
  }
}

class AiAssistantBubble extends StatelessWidget {
  const AiAssistantBubble({
    super.key,
    required this.dark,
    required this.i18n,
    required this.message,
    required this.onComingSoon,
    required this.fileCache,
    required this.onNeedFile,
    this.imageBytes,
    this.query = '',
    this.onLongPress,
    this.onImageTap,
    this.onMarkdownImage,
    this.onViewOriginal,
  });

  final bool dark;
  final AiAssistantI18n i18n;
  final AiAssistantMessage message;
  final ValueChanged<String> onComingSoon;
  final Map<String, Uint8List> fileCache;
  final ValueChanged<String> onNeedFile;
  final Uint8List? imageBytes;
  final String query;
  final VoidCallback? onLongPress;
  final VoidCallback? onImageTap;
  final ValueChanged<String>? onMarkdownImage;
  final VoidCallback? onViewOriginal;

  @override
  Widget build(BuildContext context) {
    final kind = message.outputKind;
    final Widget child;
    switch (kind) {
      case AiAssistantOutputKind.thinking:
        child = AiThinkingCard(dark: dark, i18n: i18n);
      case AiAssistantOutputKind.summary:
        child = AiSummaryCard(dark: dark, data: message.summary, query: query);
      case AiAssistantOutputKind.image:
        child = AiPosterCard(
          dark: dark,
          bytes: imageBytes,
          imageUrl: message.imageUrl,
          onTap: onImageTap,
        );
      case AiAssistantOutputKind.fileAnalysis:
        child = AiAnalysisCard(
          dark: dark,
          i18n: i18n,
          data: message.analysis,
          query: query,
          onViewOriginal: onViewOriginal ??
              () => onComingSoon(
                    i18n.t(
                      zhHans: '查看原文件',
                      zhHant: '查看原檔案',
                      en: 'View original',
                      ja: '元のファイルを見る',
                      ko: '원본 보기',
                    ),
                  ),
        );
      case AiAssistantOutputKind.code:
        child = AiCodeCard(dark: dark, data: message.code, query: query);
      case AiAssistantOutputKind.text:
      case null:
        child = AiAssistantMarkdown(
          dark: dark,
          text: message.text ?? '',
          fileCache: fileCache,
          onNeedFile: onNeedFile,
          onImageTap: onMarkdownImage,
          query: query,
        );
    }
    return AiAssistantTextCard(
      dark: dark,
      time: kind == AiAssistantOutputKind.thinking ? '' : message.time,
      onLongPress: onLongPress,
      child: child,
    );
  }
}
