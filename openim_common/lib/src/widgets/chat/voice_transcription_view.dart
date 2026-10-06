import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/voice_transcription_state.dart';
import '../../res/app_tokens.dart';
import 'voice/chat_voice_palette.dart';
import 'voice/voice_transcription_tokens.dart';

/// A voice message's local transcript, with progress and retry feedback.
class VoiceTranscriptionView extends StatelessWidget {
  const VoiceTranscriptionView({
    super.key,
    required this.state,
    this.selectable = true,
    this.onToggle,
    this.onRetry,
  });

  final VoiceTranscriptionState state;
  final bool selectable;
  final VoidCallback? onToggle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ChatVoicePalette.of(context);
    final textStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: palette.text,
      fontSize: VoiceTranscriptionTokens.textSize,
      height: VoiceTranscriptionTokens.textLineHeight,
      fontWeight: FontWeight.w400,
    );
    final statusStyle = textStyle.copyWith(
      color: palette.secondary,
      fontSize: VoiceTranscriptionTokens.statusSize,
      height: VoiceTranscriptionTokens.statusLineHeight,
    );
    final text = state.text?.trim() ?? '';
    final error = state.error?.trim();
    final failed = error != null && error.isNotEmpty;

    return Container(
      key: const ValueKey('voice-transcription-view'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppTokens.s3),
      padding: const EdgeInsets.only(top: AppTokens.s4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final canCollapse = onToggle != null &&
            _exceedsPreview(context, text, textStyle, constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.loading)
              Semantics(
                key: const ValueKey('voice-transcription-loading'),
                liveRegion: true,
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: CupertinoActivityIndicator(
                        radius: VoiceTranscriptionTokens.progressRadius,
                        color: palette.accent,
                        animating: !MediaQuery.disableAnimationsOf(context),
                      ),
                    ),
                    const SizedBox(width: AppTokens.s3),
                    Expanded(
                      child: Text('voiceToTextLoading'.tr, style: statusStyle),
                    ),
                  ],
                ),
              )
            else if (state.hasText) ...[
              if (selectable)
                TextSelectionTheme(
                  data: TextSelectionTheme.of(context).copyWith(
                    selectionColor: palette.accent
                        .withValues(alpha: ChatComposerTokens.selectionOpacity),
                    selectionHandleColor: palette.accent,
                  ),
                  child: SelectableText(
                    text,
                    key: const ValueKey('voice-transcription-text'),
                    maxLines: state.expanded
                        ? null
                        : VoiceTranscriptionTokens.collapsedLines,
                    style: textStyle,
                  ),
                )
              else
                Text(
                  text,
                  key: const ValueKey('voice-transcription-text'),
                  maxLines: state.expanded
                      ? null
                      : VoiceTranscriptionTokens.collapsedLines,
                  overflow: state.expanded ? null : TextOverflow.ellipsis,
                  style: textStyle,
                ),
              if (canCollapse)
                _action(
                  key: const ValueKey('voice-transcription-toggle'),
                  palette: palette,
                  style: statusStyle,
                  icon: state.expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  label: state.expanded
                      ? 'voiceToTextCollapse'.tr
                      : 'voiceToTextExpand'.tr,
                  onPressed: onToggle!,
                  trailingIcon: true,
                ),
            ] else ...[
              Semantics(
                key: const ValueKey('voice-transcription-feedback'),
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      failed ? 'voiceToTextFailed'.tr : 'voiceToTextEmpty'.tr,
                      style: statusStyle.copyWith(
                        color: failed ? palette.text : palette.secondary,
                        fontWeight: failed ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                    if (error != null &&
                        error.isNotEmpty &&
                        error.tr != 'voiceToTextFailed'.tr) ...[
                      const SizedBox(height: AppTokens.s2),
                      Text(error.tr, style: statusStyle),
                    ],
                  ],
                ),
              ),
              if (onRetry != null)
                _action(
                  key: const ValueKey('voice-transcription-retry'),
                  palette: palette,
                  style: statusStyle,
                  icon: Icons.refresh_rounded,
                  label: 'voiceToTextRetry'.tr,
                  onPressed: onRetry!,
                ),
            ],
          ],
        );
      }),
    );
  }

  /// Only show the folding action when there is actually more than the preview.
  /// The controller remains the owner of the expanded flag.
  bool _exceedsPreview(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
  ) {
    if (text.isEmpty || !width.isFinite || width <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: VoiceTranscriptionTokens.collapsedLines,
    )..layout(maxWidth: width);
    final exceeds = painter.didExceedMaxLines;
    painter.dispose();
    return exceeds;
  }

  Widget _action({
    required Key key,
    required ChatVoicePalette palette,
    required TextStyle style,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool trailingIcon = false,
  }) {
    final glyph = ExcludeSemantics(
      child: Icon(icon, size: VoiceTranscriptionTokens.actionIconSize),
    );
    final caption = Flexible(child: Text(label, softWrap: true));
    return TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: palette.selectedText,
        textStyle: style.copyWith(fontWeight: FontWeight.w500),
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
        minimumSize: const Size(
          kMinInteractiveDimension,
          kMinInteractiveDimension,
        ),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rSm),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: trailingIcon
            ? [
                caption,
                const SizedBox(width: AppTokens.s2),
                glyph,
              ]
            : [
                glyph,
                const SizedBox(width: AppTokens.s2),
                caption,
              ],
      ),
    );
  }
}
