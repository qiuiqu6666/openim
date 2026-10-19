import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../localization/ai_assistant_i18n.dart';
import '../../protocol/ai_image_turn.dart';
import '../../theme/ai_palette.dart';

class AiImageTurnMessage extends StatelessWidget {
  const AiImageTurnMessage({super.key, required this.turn});
  final AiImageTurn turn;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final i18n = AiAssistantI18n.of(context);
    Widget preview(int index) => AspectRatio(
          aspectRatio: turn.images.length == 1
              ? AiMetrics.imageTurnSingleAspectRatio
              : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AiMetrics.radius12),
            child: Semantics(
              button: true,
              label:
                  '${i18n.t(zhHans: '查看完整图片', en: 'View full image')} ${index + 1}',
              child: InkWell(
                onTap: () => IMUtils.previewUrlPicture([
                  for (final image in turn.images)
                    MediaSource(url: image.url, thumbnail: image.url),
                ], currentIndex: index),
                child: Image.network(
                  turn.images[index].url,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined),
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          ),
        );
    return SizedBox(
      width: AiMetrics.imageTurnWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.images.length == 1)
            preview(0)
          else
            Row(children: [
              for (var index = 0; index < turn.images.length; index++) ...[
                if (index > 0) const SizedBox(width: AiMetrics.space8),
                Expanded(child: preview(index)),
              ],
            ]),
          const SizedBox(height: AiMetrics.space10),
          Text(turn.text,
              style: TextStyle(
                  color: AiPalette.primary(dark),
                  fontSize: AiMetrics.font14,
                  height: AiMetrics.textLineHeight)),
        ],
      ),
    );
  }
}
