import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'moments_text.dart';
import 'moments_theme.dart';

/// Keeps long posts readable without moving the reader out of the feed.
class MomentsPostText extends StatefulWidget {
  const MomentsPostText(
      {super.key,
      required this.text,
      required this.onOpen,
      this.detail = false});

  final String text;
  final VoidCallback onOpen;
  final bool detail;

  @override
  State<MomentsPostText> createState() => _MomentsPostTextState();
}

class _MomentsPostTextState extends State<MomentsPostText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(MomentsPostText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: MomentsTheme.text(momentsDark(context)),
        fontSize: MomentsLayout.bodySize,
        height: widget.detail ? 1.45 : MomentsLayout.textHeight);
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(
            text: widget.text,
            style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: MomentsLayout.previewTextLines,
      )..layout(maxWidth: constraints.maxWidth);
      final overflow = !widget.detail && painter.didExceedMaxLines;
      painter.dispose();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
            onTap: widget.detail ? null : widget.onOpen,
            child: Text(widget.text,
                style: style,
                maxLines: overflow && !_expanded
                    ? MomentsLayout.previewTextLines
                    : null,
                overflow:
                    overflow && !_expanded ? TextOverflow.ellipsis : null)),
        if (overflow)
          TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                  minimumSize: const Size(
                      MomentsLayout.touchTarget, MomentsLayout.touchTarget),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppTokens.s2)),
              child: Text(_expanded
                  ? momentsText(context, zh: '收起', en: 'Show less')
                  : momentsText(context, zh: '展开全文', en: 'Read more'))),
      ]);
    });
  }
}
