import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/ai_palette.dart';
import '../../localization/ai_assistant_i18n.dart';
import '../../models/ai_assistant_models.dart';
import 'ai_assistant_text.dart';

class AiSummaryCard extends StatelessWidget {
  const AiSummaryCard({
    super.key,
    required this.dark,
    required this.data,
    this.query = '',
  });

  final bool dark;
  final AiAssistantSummaryData? data;
  final String query;

  @override
  Widget build(BuildContext context) {
    final summary = data;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    const marks = <String>['①', '②', '③', '④'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.description_outlined,
              color: AiPalette.brand(dark),
              size: AiMetrics.dimension18,
            ),
            const SizedBox(width: AiMetrics.dimension6),
            Expanded(
              child: AiHighlightText(
                text: summary.title,
                query: query,
                style: TextStyle(
                  color: AiPalette.primary(dark),
                  fontSize: AiMetrics.font15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AiMetrics.dimension6),
        AiHighlightText(
          text: summary.meta,
          query: query,
          style: TextStyle(
            color: AiPalette.secondary(dark),
            fontSize: AiMetrics.font12,
          ),
        ),
        const SizedBox(height: AiMetrics.dimension8),
        for (var i = 0; i < summary.items.length; i++) ...[
          AiHighlightText(
            text:
                '${i < marks.length ? marks[i] : '${i + 1}.'} ${summary.items[i]}',
            query: query,
            style: TextStyle(
              color: AiPalette.primary(dark),
              fontSize: AiMetrics.font14,
              height: AiMetrics.textLineHeight,
            ),
          ),
          if (i < summary.items.length - 1)
            const SizedBox(height: AiMetrics.dimension4),
        ],
        const SizedBox(height: AiMetrics.dimension8),
        AiHighlightText(
          text: summary.footer,
          query: query,
          style: TextStyle(
            color: AiPalette.primary(dark),
            fontSize: AiMetrics.font14,
            height: AiMetrics.textLineHeight,
          ),
        ),
      ],
    );
  }
}

class AiPosterCard extends StatelessWidget {
  const AiPosterCard({
    super.key,
    required this.dark,
    this.bytes,
    this.imageUrl,
    this.onTap,
  });

  final bool dark;
  final Uint8List? bytes;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = bytes != null && bytes!.isNotEmpty;
    final waiting = !hasImage && (imageUrl ?? '').trim().isNotEmpty;
    return GestureDetector(
      onTap: hasImage ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AiMetrics.radius12),
        child: AspectRatio(
          aspectRatio: AiMetrics.imageAspectRatio,
          child: hasImage
              ? Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                )
              : ColoredBox(
                  color: AiPalette.inputBg(dark),
                  child: Center(
                    child: waiting
                        ? SizedBox(
                            width: AiMetrics.dimension22,
                            height: AiMetrics.dimension22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AiPalette.brand(dark),
                            ),
                          )
                        : Icon(
                            Icons.image_outlined,
                            color: AiPalette.secondary(dark),
                          ),
                  ),
                ),
        ),
      ),
    );
  }
}

class AiAnalysisCard extends StatelessWidget {
  const AiAnalysisCard({
    super.key,
    required this.dark,
    required this.i18n,
    required this.data,
    required this.onViewOriginal,
    this.query = '',
  });

  final bool dark;
  final AiAssistantI18n i18n;
  final AiAssistantAnalysisData? data;
  final VoidCallback onViewOriginal;
  final String query;

  @override
  Widget build(BuildContext context) {
    final analysis = data;
    if (analysis == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.bar_chart_rounded,
              color: AiPalette.brand(dark),
              size: AiMetrics.dimension18,
            ),
            const SizedBox(width: AiMetrics.dimension6),
            Text(
              i18n.t(
                zhHans: '文件分析',
                zhHant: '檔案分析',
                en: 'File analysis',
                ja: 'ファイル分析',
                ko: '파일 분석',
              ),
              style: TextStyle(
                color: AiPalette.primary(dark),
                fontSize: AiMetrics.font15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AiMetrics.dimension8),
        Row(
          children: [
            Expanded(
              child: AiHighlightText(
                text: '${analysis.fileName} 路 ${analysis.sizeLabel}',
                query: query,
                style: TextStyle(
                  color: AiPalette.secondary(dark),
                  fontSize: AiMetrics.font12,
                ),
              ),
            ),
            GestureDetector(
              onTap: onViewOriginal,
              child: Text(
                i18n.t(
                  zhHans: '查看原文件',
                  zhHant: '查看原檔案',
                  en: 'View original',
                  ja: '元のファイルを見る',
                  ko: '원본 보기',
                ),
                style: TextStyle(
                  color: AiPalette.brand(dark),
                  fontSize: AiMetrics.font12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AiMetrics.dimension8),
        for (final line in analysis.bullets) ...[
          AiHighlightText(
            text: '• $line',
            query: query,
            style: TextStyle(
              color: AiPalette.primary(dark),
              fontSize: AiMetrics.font14,
              height: AiMetrics.textLineHeight,
            ),
          ),
          const SizedBox(height: AiMetrics.dimension4),
        ],
      ],
    );
  }
}

class AiCodeCard extends StatelessWidget {
  const AiCodeCard({
    super.key,
    required this.dark,
    required this.data,
    this.query = '',
  });

  final bool dark;
  final AiAssistantCodeData? data;
  final String query;

  @override
  Widget build(BuildContext context) {
    final code = data;
    if (code == null) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? AiPalette.codeDark : AiPalette.codeLight,
        borderRadius: BorderRadius.circular(AiMetrics.radius12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AiMetrics.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AiHighlightText(
              text: code.language,
              query: query,
              style: TextStyle(
                color: AiPalette.secondary(true),
                fontSize: AiMetrics.font12,
              ),
            ),
            const SizedBox(height: AiMetrics.dimension8),
            AiHighlightText(
              text: code.source,
              query: query,
              style: const TextStyle(
                color: AiPalette.codeText,
                fontSize: AiMetrics.font13,
                height: AiMetrics.textLineHeight,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiThinkingCard extends StatefulWidget {
  const AiThinkingCard({super.key, required this.dark, required this.i18n});

  final bool dark;
  final AiAssistantI18n i18n;

  @override
  State<AiThinkingCard> createState() => AiThinkingCardState();
}

class AiThinkingCardState extends State<AiThinkingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AiMetrics.thinkingAnimationDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = .5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              Opacity(
                opacity: 0.3 +
                    0.7 *
                        Curves.easeInOut.transform(
                          (_controller.value + i * 0.2) % 1.0,
                        ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AiPalette.brand(widget.dark),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                      width: AiMetrics.dimension6,
                      height: AiMetrics.dimension6),
                ),
              ),
              if (i < 2) const SizedBox(width: AiMetrics.dimension4),
            ],
            const SizedBox(width: AiMetrics.dimension8),
            child!,
          ],
        );
      },
      child: Text(
        widget.i18n.t(
          zhHans: '思考中',
          zhHant: '思考中',
          en: 'Thinking',
          ja: '考え中',
          ko: '생각 중',
        ),
        style: TextStyle(
          color: AiPalette.primary(widget.dark),
          fontSize: AiMetrics.font15,
        ),
      ),
    );
  }
}
