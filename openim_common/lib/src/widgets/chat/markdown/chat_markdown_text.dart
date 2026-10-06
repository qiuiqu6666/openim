import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../utils/image_util.dart';
import '../../text_view.dart';
import 'chat_markdown_patterns.dart';
import 'chat_markdown_styles.dart';

/// GitHub-flavored Markdown for a text bubble; the caller owns SDK data,
/// gestures, copying, and routing. Copy callbacks keep the source Markdown.
class ChatMarkdownText extends StatefulWidget {
  const ChatMarkdownText({
    super.key,
    required this.text,
    required this.textStyle,
    this.matchTextStyle,
    this.patterns = const <MatchPattern>[],
    this.textScaler,
    this.onVisibleTrulyText,
  });

  final String text;
  final TextStyle textStyle;
  final TextStyle? matchTextStyle;
  final List<MatchPattern> patterns;
  final TextScaler? textScaler;
  final Function(String? text)? onVisibleTrulyText;

  static final _inline = RegExp(
    r'(\*{1,3}|_{1,3}|~~|`+)(?=\S)[^\r\n]*?\S\1|!?\[[^\]\n]*\]\([^\n]*\)|!?\[[^\]\n]+\]\[[^\]\n]*\]|<https?://[^>]+>|\\[\\`*_{}\[\]()#+\-.!<>~|]',
  );
  static final _block = RegExp(
    r'^[ \t]{0,3}(?:#{1,6}[ \t]+|>[ \t]?|[-+*][ \t]+|\d+[.)][ \t]+|`{3,}|~{3,}|\[[^\]\n]+\]:[ \t]*\S)|^(?: {4,}|\t)[ \t]*\S|^[ \t]{0,3}(?:[-*_][ \t]*){3,}$|^[ \t]*(?:=+|-+)[ \t]*$|^[ \t]*\|?\s*:?-+:?\s*\|',
    multiLine: true,
  );

  /// Keeps ordinary text, email addresses and bare URLs on the existing path.
  static bool hasMarkdown(String text) =>
      _inline.hasMatch(text) || _block.hasMatch(text);

  @override
  State<ChatMarkdownText> createState() => _ChatMarkdownTextState();
}

class _ChatMarkdownTextState extends State<ChatMarkdownText> {
  final _recognizers = <(int, String), TapGestureRecognizer>{};
  List<(PatternType, String?, TextStyle?, bool)> _patternConfiguration = [];
  String? _source;
  var _configurationRevision = 0;

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configuration = [
      for (final pattern in widget.patterns)
        (pattern.type, pattern.pattern, pattern.style, pattern.onTap != null),
    ];
    if (_source != widget.text ||
        !listEquals(_patternConfiguration, configuration)) {
      _disposeRecognizers();
      _source = widget.text;
      _patternConfiguration = configuration;
      _configurationRevision++;
    }
    widget.onVisibleTrulyText?.call(widget.text);
    final styles = ChatMarkdownStyles.of(
      context,
      body: widget.textStyle,
      link: widget.matchTextStyle,
      textScaler: widget.textScaler,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      return SizedBox(
        width: width,
        child: MarkdownBody(
          // Markdown caches parsed widgets. Reparse when match syntax/styles
          // change, while callback-only rebuilds reuse safe live recognizers.
          key: ValueKey(_configurationRevision),
          data: widget.text,
          styleSheet: styles,
          extensionSet: md.ExtensionSet.gitHubFlavored,
          inlineSyntaxes:
              ChatMarkdownPatternSyntax.forPatterns(widget.patterns),
          // Newlines in a chat message remain meaningful line breaks.
          softLineBreak: true,
          selectable: false,
          fitContent: false,
          listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
          onTapLink: (_, href, __) => _tapLink(href),
          builders: {
            ChatMarkdownPatternSyntax.tag: _MatchBuilder(
              patterns: widget.patterns,
              fallbackStyle: styles.a!,
              textScaler: styles.textScaler!,
              createRecognizer: (index, value) {
                final pattern = widget.patterns[index];
                if (pattern.onTap == null) return null;
                final target = ChatMarkdownPatternSyntax.target(
                  value,
                  pattern.type,
                );
                if (pattern.type != PatternType.custom &&
                    !ChatMarkdownPatternSyntax.isSafeLink(target)) {
                  return null;
                }
                return _recognizers.putIfAbsent((index, value), () {
                  return TapGestureRecognizer()
                    ..onTap = () {
                      final current = widget.patterns[index];
                      current.onTap?.call(target, current.type);
                    };
                });
              },
            ),
            'pre': _WrappingCodeBuilder(styles.code!, styles.textScaler!),
          },
          sizedImageBuilder: (config) =>
              _image(context, config.uri, config.alt, width),
        ),
      );
    });
  }

  void _tapLink(String? href) {
    if (href == null || !ChatMarkdownPatternSyntax.isSafeLink(href)) return;
    final scheme = Uri.parse(href.trim()).scheme.toLowerCase();
    final types = switch (scheme) {
      'mailto' => const [PatternType.email],
      'tel' => const [PatternType.mobile, PatternType.tel],
      _ => const [PatternType.url],
    };
    for (final pattern in widget.patterns) {
      if (types.contains(pattern.type) && pattern.onTap != null) {
        pattern.onTap!(href.trim(), pattern.type);
        return;
      }
    }
  }

  Widget _image(BuildContext context, Uri uri, String? alt, double width) {
    final color =
        widget.textStyle.color ?? Theme.of(context).colorScheme.onSurface;
    final placeholder = AspectRatio(
      aspectRatio: ChatMarkdownStyles.imageAspectRatio,
      child: ColoredBox(
        color: color.withValues(alpha: 0.08),
        child: Center(child: Icon(Icons.image_outlined, color: color)),
      ),
    );
    final remote =
        (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
    return Semantics(
      label: alt,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ChatMarkdownStyles.imageRadius),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: width),
          child: remote
              ? ImageUtil.networkImage(
                  url: uri.toString(),
                  width: width,
                  cacheWidth: ImageUtil.decodeDimension(
                    width,
                    MediaQuery.devicePixelRatioOf(context),
                  ),
                  fit: BoxFit.contain,
                  loadingWidget: placeholder,
                  errorWidget: placeholder,
                )
              : placeholder,
        ),
      ),
    );
  }
}

class _MatchBuilder extends MarkdownElementBuilder {
  _MatchBuilder({
    required this.patterns,
    required this.fallbackStyle,
    required this.textScaler,
    required this.createRecognizer,
  });

  final List<MatchPattern> patterns;
  final TextStyle fallbackStyle;
  final TextScaler textScaler;
  final GestureRecognizer? Function(int, String) createRecognizer;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final index = int.tryParse(element.attributes['index'] ?? '');
    if (index == null || index < 0 || index >= patterns.length) return null;
    final pattern = patterns[index];
    final text = element.textContent;
    return Text.rich(
      TextSpan(
        // The invisible breaks match the existing chat URL wrapping behavior.
        text: text.split('').join('\u200B'),
        style: (parentStyle ?? const TextStyle()).merge(
          pattern.style ??
              TextStyle(
                color: fallbackStyle.color,
                decoration: fallbackStyle.decoration,
                decorationColor: fallbackStyle.decorationColor,
              ),
        ),
        recognizer: createRecognizer(index, text),
      ),
      textScaler: textScaler,
    );
  }
}

class _WrappingCodeBuilder extends MarkdownElementBuilder {
  _WrappingCodeBuilder(this.style, this.scaler);

  final TextStyle style;
  final TextScaler scaler;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => Padding(
        padding: ChatMarkdownStyles.codePadding,
        child: Text(
          text.text.replaceFirst(RegExp(r'\n$'), ''),
          style: style.copyWith(backgroundColor: Colors.transparent),
          textScaler: scaler,
          softWrap: true,
        ),
      );
}
