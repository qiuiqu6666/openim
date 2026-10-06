import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../theme/ai_palette.dart';
import '../../localization/ai_assistant_i18n.dart';
import '../../models/ai_assistant_models.dart';
import '../../composer/ai_assistant_draft.dart';
import 'ai_assistant_file_kind.dart';

class AiDraftBar extends StatelessWidget {
  const AiDraftBar({
    super.key,
    required this.dark,
    required this.i18n,
    required this.drafts,
    required this.onRemove,
  });

  final bool dark;
  final AiAssistantI18n i18n;
  final List<AiAssistantDraftItem> drafts;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AiMetrics.dimension56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AiMetrics.space12),
        scrollDirection: Axis.horizontal,
        itemCount: drafts.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AiMetrics.dimension8),
        itemBuilder: (context, index) {
          final item = drafts[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              _draftBody(item),
              Positioned(
                top: AiMetrics.positionMinus4,
                right: AiMetrics.positionMinus4,
                child: InkWell(
                  onTap: () => onRemove(index),
                  customBorder: const CircleBorder(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AiPalette.cardBg(dark),
                      shape: BoxShape.circle,
                      border: Border.all(color: AiPalette.line(dark)),
                    ),
                    child: const SizedBox(
                      width: AiMetrics.dimension16,
                      height: AiMetrics.dimension16,
                      child: Icon(Icons.close_rounded,
                          size: AiMetrics.dimension12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _draftBody(AiAssistantDraftItem item) {
    final card = item.card;
    if (card != null) {
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
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AiPalette.cardBg(dark),
          borderRadius: BorderRadius.circular(AiMetrics.radius12),
          border: Border.all(color: AiPalette.line(dark)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AiMetrics.space8),
          child: Row(
            children: [
              AvatarView(
                url: card.faceUrl,
                text: card.name,
                width: AiMetrics.dimension32,
                height: AiMetrics.dimension32,
                isGroup: card.kind == AiAssistantCardKind.group,
              ),
              const SizedBox(width: AiMetrics.dimension6),
              SizedBox(
                width: AiMetrics.dimension88,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AiPalette.primary(dark),
                        fontSize: AiMetrics.font12,
                      ),
                    ),
                    Text(
                      badge,
                      style: TextStyle(
                        color: AiPalette.secondary(dark),
                        fontSize: AiMetrics.font10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final file = item.file;
    if (file == null) {
      return const SizedBox.shrink();
    }
    final path = file.localPath ?? '';
    final bytes = file.bytes;
    if (file.kind == AiAssistantFileKind.image &&
        bytes != null &&
        bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AiMetrics.radius8),
        child: Image.memory(
          bytes,
          width: AiMetrics.dimension48,
          height: AiMetrics.dimension48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _draftFileIcon(file),
        ),
      );
    }
    if (file.kind == AiAssistantFileKind.image && path.isNotEmpty && !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AiMetrics.radius8),
        child: Image.file(
          File(path),
          width: AiMetrics.dimension48,
          height: AiMetrics.dimension48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _draftFileIcon(file),
        ),
      );
    }
    return _draftFileIcon(file);
  }

  Widget _draftFileIcon(AiAssistantFileRef file) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AiPalette.cardBg(dark),
        borderRadius: BorderRadius.circular(AiMetrics.radius12),
        border: Border.all(color: AiPalette.line(dark)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AiMetrics.space8),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AiAssistantFileKinds.color(file.kind),
                borderRadius:
                    const BorderRadius.all(Radius.circular(AiMetrics.radius6)),
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
            const SizedBox(width: AiMetrics.dimension6),
            SizedBox(
              width: AiMetrics.dimension88,
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AiPalette.primary(dark),
                  fontSize: AiMetrics.font12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
