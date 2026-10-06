import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../theme/ai_palette.dart';
import '../../localization/ai_assistant_i18n.dart';
import '../../models/ai_assistant_models.dart';
import '../../data/ai_assistant_upload_mime.dart';
import 'ai_assistant_text.dart';
import '../composer/ai_assistant_file_kind.dart';

class AiUserCardRow extends StatelessWidget {
  const AiUserCardRow({
    super.key,
    required this.dark,
    required this.card,
    required this.onTap,
    this.query = '',
  });

  final bool dark;
  final AiAssistantCardRef card;
  final VoidCallback onTap;
  final String query;

  @override
  Widget build(BuildContext context) {
    final i18n = AiAssistantI18n.of(context);
    final badge = card.kind == AiAssistantCardKind.friend
        ? i18n.t(
            zhHans: '好友',
            zhHant: '好友',
            en: 'Friend',
            ja: '友だち',
            ko: '친구',
          )
        : i18n.t(
            zhHans: '群',
            zhHant: '群',
            en: 'Group',
            ja: 'グループ',
            ko: '그룹',
          );
    return Material(
      color: AiPalette.cardBg(dark),
      borderRadius: BorderRadius.circular(AiMetrics.radius12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AiMetrics.radius12),
        child: Container(
          padding: const EdgeInsets.all(AiMetrics.space10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AiMetrics.radius12),
            border: Border.all(color: AiPalette.line(dark)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarView(
                url: card.faceUrl,
                text: card.name,
                width: AiMetrics.dimension32,
                height: AiMetrics.dimension32,
                isGroup: card.kind == AiAssistantCardKind.group,
              ),
              const SizedBox(width: AiMetrics.dimension8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AiHighlightText(
                      text: card.name,
                      query: query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AiPalette.primary(dark),
                        fontSize: AiMetrics.font13,
                      ),
                    ),
                    Text(
                      badge,
                      style: TextStyle(
                        color: AiPalette.secondary(dark),
                        fontSize: AiMetrics.font11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool aiCanShowUserImage(
  AiAssistantFileRef file,
  Map<String, Uint8List> fileCache,
) {
  final bytes = file.bytes ?? fileCache[(file.fileId ?? '').trim()];
  if (bytes != null && bytes.isNotEmpty) {
    return AiAssistantUploadMime.isImageBytes(bytes);
  }
  return file.kind == AiAssistantFileKind.image &&
      (file.localPath ?? '').isNotEmpty;
}

class AiUserImageThumb extends StatelessWidget {
  const AiUserImageThumb({
    super.key,
    required this.dark,
    required this.file,
    required this.onTap,
    this.bytes,
    this.query = '',
  });

  final bool dark;
  final AiAssistantFileRef file;
  final VoidCallback onTap;
  final Uint8List? bytes;
  final String query;

  @override
  Widget build(BuildContext context) {
    final path = file.localPath ?? '';
    final data = bytes ?? file.bytes;
    final Widget child;
    if (data != null && data.isNotEmpty) {
      child = Image.memory(
        data,
        width: AiMetrics.dimension96,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => AiUserFileRow(
          dark: dark,
          file: file,
          onTap: onTap,
          query: query,
        ),
      );
    } else if (!kIsWeb && path.isNotEmpty) {
      child = Image.file(
        File(path),
        width: AiMetrics.dimension96,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => AiUserFileRow(
          dark: dark,
          file: file,
          onTap: onTap,
          query: query,
        ),
      );
    } else {
      child = AiUserFileRow(
        dark: dark,
        file: file,
        onTap: onTap,
        query: query,
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AiMetrics.radius8),
        child: SizedBox(width: AiMetrics.dimension96, child: child),
      ),
    );
  }
}

class AiUserFileRow extends StatelessWidget {
  const AiUserFileRow({
    super.key,
    required this.dark,
    required this.file,
    required this.onTap,
    this.query = '',
  });

  final bool dark;
  final AiAssistantFileRef file;
  final VoidCallback onTap;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AiPalette.cardBg(dark),
      borderRadius: BorderRadius.circular(AiMetrics.radius12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AiMetrics.radius12),
        child: Container(
          padding: const EdgeInsets.all(AiMetrics.space10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AiMetrics.radius12),
            border: Border.all(color: AiPalette.line(dark)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AiAssistantFileKinds.color(file.kind),
                      borderRadius: const BorderRadius.all(
                          Radius.circular(AiMetrics.radius6)),
                    ),
                    child: SizedBox(
                      width: AiMetrics.dimension28,
                      height: AiMetrics.dimension28,
                      child: Icon(
                        AiAssistantFileKinds.icon(file.kind),
                        color: AiPalette.onAccent,
                        size: AiMetrics.dimension16,
                      ),
                    ),
                  ),
                  const SizedBox(width: AiMetrics.dimension8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(
                          0,
                          constraints.maxWidth -
                              AiMetrics.dimension28 -
                              AiMetrics.space8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AiHighlightText(
                          text: file.name,
                          query: query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AiPalette.primary(dark),
                            fontSize: AiMetrics.font13,
                          ),
                        ),
                        Text(
                          file.sizeLabel,
                          style: TextStyle(
                            color: AiPalette.secondary(dark),
                            fontSize: AiMetrics.font11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
