import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../voice_to_text_service.dart';
import 'voice_text_preview_tokens.dart';

class VoiceTextChoice {
  const VoiceTextChoice.original() : text = null;
  const VoiceTextChoice.text(this.text);
  final String? text;
  bool get sendOriginal => text == null;
}

/// Owns recognition and editing; the existing chat controller owns sending.
/// The historical name remains compatible with existing callers and tests.
class VoiceTextPreviewDialog extends StatefulWidget {
  const VoiceTextPreviewDialog({super.key, required this.transcribe});
  final Future<String> Function(CancelToken cancelToken) transcribe;

  static Future<VoiceTextChoice?> show(
    BuildContext context, {
    required Future<String> Function(CancelToken cancelToken) transcribe,
  }) =>
      showModalBottomSheet<VoiceTextChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0),
        elevation: 0,
        constraints:
            const BoxConstraints(maxWidth: VoiceTextPreviewTokens.maxWidth),
        builder: (_) => VoiceTextPreviewDialog(transcribe: transcribe),
      );

  @override
  State<VoiceTextPreviewDialog> createState() => _VoiceTextPreviewDialogState();
}

class _VoiceTextPreviewDialogState extends State<VoiceTextPreviewDialog> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  CancelToken? _request;
  bool _loading = false;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_recognize());
  }

  Future<void> _recognize() async {
    // Lock before awaiting so a repeated accessibility/tap callback cannot
    // start overlapping recognition jobs or overwrite an edited result.
    if (_loading || _finishing) return;
    _request?.cancel();
    final request = _request = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = (await widget.transcribe(request)).trim();
      if (!mounted || request.isCancelled || request != _request) return;
      if (text.isEmpty) {
        _error = 'voiceToTextEmpty'.tr;
      } else {
        _text.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length));
      }
    } catch (error) {
      if (!mounted || request.isCancelled || request != _request) return;
      _error = error is VoiceToTextException
          ? error.messageKey.tr
          : 'voiceToTextFailed'.tr;
    } finally {
      if (mounted && request == _request && !request.isCancelled) {
        setState(() => _loading = false);
      }
    }
  }

  void _finish(VoiceTextChoice? choice) {
    if (_finishing || ModalRoute.of(context)?.isCurrent == false) return;
    setState(() => _finishing = true);
    _request?.cancel();
    _focus.unfocus();
    Navigator.pop(context, choice);
  }

  @override
  void dispose() {
    _request?.cancel();
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChatVoicePalette.of(context);
    final media = MediaQuery.of(context);
    final largeText = media.textScaler.scale(AppTokens.secondaryFontSize) >
        AppTokens.secondaryFontSize * VoiceTextPreviewTokens.largeTextThreshold;
    return AnimatedPadding(
      duration: media.disableAnimations
          ? Duration.zero
          : VoiceTextPreviewTokens.keyboardAnimation,
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: LayoutBuilder(builder: (context, constraints) {
        final safeBottom =
            media.viewInsets.bottom > 0 ? 0.0 : media.padding.bottom;
        final preferred = largeText
            ? VoiceTextPreviewTokens.largeTextHeight
            : VoiceTextPreviewTokens.height;
        final height = math.min(constraints.maxHeight, preferred + safeBottom);
        final stacked = largeText ||
            constraints.maxWidth < VoiceTextPreviewTokens.stackedActionWidth;
        final compact = height - safeBottom <
            (largeText
                ? VoiceTextPreviewTokens.largeTextHeight
                : VoiceTextPreviewTokens.compactHeight);
        final compactContentHeight =
            VoiceTextPreviewTokens.compactContentHeight *
                media.textScaler.scale(AppTokens.listTitleFontSize) /
                AppTokens.listTitleFontSize;
        final needsScrollFallback = height - safeBottom <
            (largeText
                ? VoiceTextPreviewTokens.largeTextScrollFallbackHeight
                : VoiceTextPreviewTokens.scrollFallbackHeight);
        final header = _header(palette);
        final actions = _actions(palette, stacked: stacked);
        final content = _content(palette, compact: compact);
        return SizedBox(
          key: const ValueKey('voice-text-sheet'),
          height: height,
          width: double.infinity,
          child: Material(
            color: palette.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(VoiceTextPreviewTokens.radius)),
            child: Padding(
              padding: EdgeInsets.only(bottom: safeBottom),
              child: needsScrollFallback
                  ? SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        header,
                        SizedBox(height: compactContentHeight, child: content),
                        actions,
                      ]),
                    )
                  : Column(
                      children: [header, Expanded(child: content), actions]),
            ),
          ),
        );
      }),
    );
  }

  Widget _header(ChatVoicePalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(VoiceTextPreviewTokens.inset,
            AppTokens.s4, AppTokens.s4, AppTokens.s3),
        child: Row(children: [
          Expanded(
            child: Text('voiceTextPreview'.tr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: AppTokens.listTitleFontSize,
                    fontWeight: FontWeight.w600,
                    color: palette.text)),
          ),
          const SizedBox(width: AppTokens.s3),
          IconButton(
            key: const ValueKey('voice-text-close'),
            tooltip: StrRes.cancel,
            onPressed: _finishing ? null : () => _finish(null),
            style: IconButton.styleFrom(
                minimumSize:
                    const Size.square(VoiceTextPreviewTokens.closeSize),
                foregroundColor: palette.secondary,
                backgroundColor: palette.controlSurface),
            icon: const Icon(Icons.close_rounded,
                size: AppTokens.profileQrIconSize),
          ),
        ]),
      );

  Widget _content(ChatVoicePalette palette, {required bool compact}) {
    final theme = Theme.of(context);
    final description = theme.textTheme.bodyMedium?.copyWith(
        fontSize: AppTokens.secondaryFontSize,
        height: VoiceTextPreviewTokens.bodyLineHeight,
        color: palette.secondary);
    if (_loading || _error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: VoiceTextPreviewTokens.inset, vertical: AppTokens.s4),
          child: Semantics(
            liveRegion: true,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_loading) ...[
                CupertinoActivityIndicator(
                    radius: VoiceTextPreviewTokens.spinnerRadius,
                    color: palette.accent,
                    animating: !MediaQuery.disableAnimationsOf(context)),
                const SizedBox(height: AppTokens.s5),
              ],
              Text(_loading ? 'voiceToTextLoading'.tr : _error!,
                  key: const ValueKey('voice-text-status'),
                  textAlign: TextAlign.center,
                  style: description),
              if (!_loading)
                TextButton(
                  key: const ValueKey('voice-text-retry'),
                  onPressed: _finishing ? null : _recognize,
                  style: TextButton.styleFrom(
                      foregroundColor: palette.selectedText,
                      minimumSize:
                          const Size(0, VoiceTextPreviewTokens.actionHeight)),
                  child: Text('voiceToTextRetry'.tr),
                ),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: VoiceTextPreviewTokens.inset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!compact) ...[
          Text('voiceTextEditHint'.tr, style: description),
          const SizedBox(height: AppTokens.s4),
        ],
        Expanded(
          child: Semantics(
            label: 'voiceTextEditHint'.tr,
            child: TextField(
              key: const ValueKey('voice-text-editor'),
              controller: _text,
              focusNode: _focus,
              readOnly: _finishing,
              expands: true,
              minLines: null,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: palette.accent,
              onChanged: (_) => setState(() {}),
              style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: AppTokens.listTitleFontSize,
                  height: VoiceTextPreviewTokens.bodyLineHeight,
                  color: palette.text),
              decoration: InputDecoration(
                filled: true,
                fillColor: palette.controlSurface,
                contentPadding: const EdgeInsets.all(AppTokens.s5),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rMd),
                    borderSide: BorderSide(color: palette.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.rMd),
                    borderSide: BorderSide(color: palette.accent)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _actions(ChatVoicePalette palette, {required bool stacked}) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.rMd));
    final original = TextButton(
      key: const ValueKey('voice-text-original'),
      onPressed:
          _finishing ? null : () => _finish(const VoiceTextChoice.original()),
      style: TextButton.styleFrom(
          foregroundColor: palette.selectedText,
          minimumSize: const Size(0, VoiceTextPreviewTokens.actionHeight),
          shape: shape),
      child: Text('voiceSendOriginal'.tr, textAlign: TextAlign.center),
    );
    final send = FilledButton(
      key: const ValueKey('voice-text-send'),
      onPressed:
          _finishing || _loading || _error != null || _text.text.trim().isEmpty
              ? null
              : () => _finish(VoiceTextChoice.text(_text.text.trim())),
      style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          disabledBackgroundColor: palette.controlSurface,
          disabledForegroundColor: palette.secondary,
          minimumSize: const Size(0, VoiceTextPreviewTokens.actionHeight),
          shape: shape),
      child: Text('voiceSendText'.tr, textAlign: TextAlign.center),
    );
    return Padding(
      padding: const EdgeInsets.all(VoiceTextPreviewTokens.inset),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [send, const SizedBox(height: AppTokens.s3), original])
          : Row(children: [
              Expanded(child: original),
              const SizedBox(width: AppTokens.s4),
              Expanded(child: send)
            ]),
    );
  }
}
