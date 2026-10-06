import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../theme/ai_palette.dart';
import '../../data/ai_assistant_api.dart';
import '../../search/ai_assistant_search.dart';

class AiHighlightText extends StatelessWidget {
  const AiHighlightText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: AiAssistantSearch.highlight(
          text,
          query,
          base: style,
          hit: style.copyWith(
            backgroundColor: AiPalette.searchHit,
            color: AiPalette.text,
          ),
        ),
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

class _MarkdownSearchHighlightBuilder extends MarkdownElementBuilder {
  _MarkdownSearchHighlightBuilder({
    required this.query,
    required this.fallbackStyle,
  });

  final String query;
  final TextStyle fallbackStyle;

  @override
  Widget? visitText(text, TextStyle? preferredStyle) {
    return AiHighlightText(
      text: text.text,
      query: query,
      style: preferredStyle ?? fallbackStyle,
    );
  }
}

class AiAssistantMarkdown extends StatelessWidget {
  const AiAssistantMarkdown({
    super.key,
    required this.dark,
    required this.text,
    required this.fileCache,
    required this.onNeedFile,
    this.onImageTap,
    this.query = '',
  });

  final bool dark;
  final String text;
  final Map<String, Uint8List> fileCache;
  final ValueChanged<String> onNeedFile;
  final ValueChanged<String>? onImageTap;
  final String query;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AiPalette.primary(dark),
      fontSize: AiMetrics.font15,
      height: AiMetrics.textLineHeight,
    );
    final needle = AiAssistantSearch.normalize(query);
    final highlightBuilder = _MarkdownSearchHighlightBuilder(
      query: query,
      fallbackStyle: style,
    );
    final cacheIdentity = Object.hashAll(fileCache.entries
        .map((entry) => Object.hash(entry.key, identityHashCode(entry.value))));
    return MarkdownBody(
      // Markdown caches parsed widgets; refresh search hits and private images.
      key: ValueKey((query, cacheIdentity)),
      data: text,
      shrinkWrap: true,
      builders: needle.isEmpty
          ? const <String, MarkdownElementBuilder>{}
          : <String, MarkdownElementBuilder>{
              'p': highlightBuilder,
              'h1': highlightBuilder,
              'h2': highlightBuilder,
              'h3': highlightBuilder,
              'h4': highlightBuilder,
              'h5': highlightBuilder,
              'h6': highlightBuilder,
              'li': highlightBuilder,
              'pre': highlightBuilder,
              'blockquote': highlightBuilder,
            },
      styleSheet: MarkdownStyleSheet(
        p: style,
        strong: style.copyWith(fontWeight: FontWeight.w600),
        em: style.copyWith(fontStyle: FontStyle.italic),
        listBullet: style,
        listIndent: AiMetrics.dimension22,
        blockSpacing: AiMetrics.dimension10,
        pPadding: const EdgeInsets.only(bottom: AiMetrics.space6),
        h1: style.copyWith(
            fontSize: AiMetrics.font18, fontWeight: FontWeight.w700),
        h2: style.copyWith(
            fontSize: AiMetrics.font17, fontWeight: FontWeight.w700),
        h3: style.copyWith(
            fontSize: AiMetrics.font16, fontWeight: FontWeight.w600),
      ),
      sizedImageBuilder: (config) {
        return _buildImage(context, config.uri.toString());
      },
    );
  }

  Widget _buildImage(BuildContext context, String raw) {
    final id = AiAssistantApi.fileIdFromUrl(raw);
    if (id != null) {
      final bytes = fileCache[id];
      if (bytes == null || bytes.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) onNeedFile(id);
        });
        return _placeholder(waiting: true);
      }
      return GestureDetector(
        onTap: () => onImageTap?.call(raw),
        child: _frame(
          Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _placeholder(waiting: false),
          ),
        ),
      );
    }
    if (raw.contains('/api/v1/chat/files/')) {
      return _placeholder(waiting: true);
    }
    return _placeholder(waiting: false);
  }

  Widget _frame(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AiMetrics.space8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AiMetrics.radius12),
        child: child,
      ),
    );
  }

  Widget _placeholder({required bool waiting}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AiMetrics.space8),
      child: AspectRatio(
        aspectRatio: AiMetrics.imageAspectRatio,
        child: ColoredBox(
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
    );
  }
}

class AiAssistantAvatar extends StatelessWidget {
  const AiAssistantAvatar({super.key, this.size = 32});

  static const _asset = 'assets/ai/99chat.webp';

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class AiAssistantTextCard extends StatelessWidget {
  const AiAssistantTextCard({
    super.key,
    required this.dark,
    required this.time,
    required this.child,
    this.onLongPress,
  });

  final bool dark;
  final String time;
  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final maxWidth =
        MediaQuery.sizeOf(context).width * AiMetrics.bubbleWidthRatio;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AiAssistantAvatar(),
        const SizedBox(width: AiMetrics.dimension8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AiPalette.cardBg(dark),
                    borderRadius: BorderRadius.circular(AiMetrics.radius16),
                    border: Border.all(color: AiPalette.line(dark)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AiMetrics.space12),
                    child: child,
                  ),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(height: AiMetrics.dimension4),
                Text(
                  time,
                  style: TextStyle(
                    color: AiPalette.secondary(dark),
                    fontSize: AiMetrics.font11,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Spacer(),
      ],
    );
  }
}
