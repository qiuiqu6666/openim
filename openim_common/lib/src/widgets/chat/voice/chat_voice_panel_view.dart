import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../res/chat_voice_tokens.dart';
import 'chat_voice_palette.dart';
import 'chat_voice_panel_layout.dart';
import 'chat_voice_waveform.dart';

/// Presentation only. Pointer handling and recorder ownership stay upstream.
class ChatVoiceIdlePanel extends StatelessWidget {
  const ChatVoiceIdlePanel({
    super.key,
    required this.height,
    required this.micKey,
    this.active = false,
    this.busy = false,
    this.errorText,
  });

  final double height;
  final GlobalKey micKey;
  final bool active;
  final bool busy;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final palette = ChatVoicePalette.of(context);
    final error = errorText?.trim() ?? '';
    final hasError = error.isNotEmpty;
    final largeText =
        MediaQuery.textScalerOf(context).scale(ChatVoiceTokens.hintFontSize) >
            ChatVoiceTokens.hintFontSize * ChatVoiceTokens.largeTextScale;
    const belowMic = ChatVoiceTokens.mainCenterY +
        ChatVoiceTokens.micSize / 2 +
        ChatVoiceTokens.controlLabelGap;
    final titleTop =
        largeText && hasError ? belowMic : ChatVoiceTokens.headerTop;
    final hintTop = largeText
        ? (hasError ? ChatVoiceTokens.headerTop : belowMic)
        : ChatVoiceTokens.hintTop;
    final title = busy
        ? '正在处理…'
        : active
            ? '松开发送'
            : '按住说话';
    final hint = hasError
        ? error
        : busy
            ? (largeText ? '请稍候' : '正在处理录音，请稍候')
            : (largeText ? '松开发送，滑动切换' : '松开发送，向两侧滑动切换操作');
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ChatVoiceTokens.stateAnimation;
    return ColoredBox(
      key: const ValueKey('chat-voice-idle-panel'),
      color: palette.surface,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(children: [
          Positioned(
            left: ChatVoiceTokens.horizontalInset,
            right: ChatVoiceTokens.horizontalInset,
            top: titleTop,
            child: Text(
              title,
              key: const ValueKey('chat-voice-idle-title'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ChatVoiceTokens.titleFontSize,
                height: ChatVoiceTokens.textLineHeight,
                fontWeight: FontWeight.w500,
                color: palette.text,
              ),
            ),
          ),
          Positioned(
            left: ChatVoiceTokens.horizontalInset,
            right: ChatVoiceTokens.horizontalInset,
            top: hintTop,
            child: Semantics(
              liveRegion: hasError,
              label: hasError ? error : null,
              excludeSemantics: hasError,
              child: Text(
                hint,
                key: const ValueKey('chat-voice-idle-hint'),
                textAlign: TextAlign.center,
                maxLines: largeText && !hasError ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ChatVoiceTokens.hintFontSize,
                  height: ChatVoiceTokens.textLineHeight,
                  color: hasError ? palette.danger : palette.secondary,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: ChatVoiceTokens.mainCenterY - ChatVoiceTokens.micSize / 2,
            child: Center(
              child: Semantics(
                button: true,
                enabled: !busy,
                label: busy ? '正在处理录音' : '按住说话',
                child: AnimatedContainer(
                  key: micKey,
                  duration: duration,
                  curve: Curves.easeOut,
                  width: ChatVoiceTokens.micSize,
                  height: ChatVoiceTokens.micSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent,
                  ),
                  child: busy
                      ? Center(
                          child: _loading(context,
                              color: palette.onAccent,
                              radius: ChatVoiceTokens.spinnerRadius))
                      : Icon(Icons.mic_rounded,
                          size: ChatVoiceTokens.micIconSize,
                          color: palette.onAccent),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Full-screen recording presentation driven by real recorder samples.
/// No gesture handlers, timers, synthesized waveforms or recording state live here.
class ChatVoiceRecordingOverlay extends StatelessWidget {
  const ChatVoiceRecordingOverlay({
    super.key,
    required this.anchorGlobal,
    required this.zone,
    this.seconds = 0,
    this.levels = const [],
    this.preparing = false,
    this.allowConvert = true,
  });

  final Offset? anchorGlobal;
  final ChatVoiceReleaseZone zone;
  final int seconds;
  final List<double> levels;
  final bool preparing;
  final bool allowConvert;

  @override
  Widget build(BuildContext context) {
    final palette = ChatVoicePalette.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenSize = MediaQuery.sizeOf(context);
    final panelHeight = ChatVoiceTokens.panelHeight + bottomInset;
    final panelTop = screenSize.height - panelHeight;
    final anchor = anchorGlobal;
    final layout = ChatVoiceControlsLayout(
      panelSize: Size(screenSize.width, panelHeight),
      bottomInset: bottomInset,
      anchorCenter:
          anchor == null ? null : Offset(anchor.dx, anchor.dy - panelTop),
    );
    final activeZone = !allowConvert && zone == ChatVoiceReleaseZone.convertText
        ? ChatVoiceReleaseZone.send
        : zone;
    return Material(
      color: Colors.transparent,
      child: Stack(children: [
        Positioned.fill(child: ColoredBox(color: palette.scrim)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: panelHeight,
          child: ColoredBox(
            key: const ValueKey('chat-voice-panel'),
            color: palette.surface,
            child: Stack(children: [
              _header(context, layout, palette, activeZone),
              Positioned(
                left: ChatVoiceTokens.waveformHorizontalInset,
                right: ChatVoiceTokens.waveformHorizontalInset,
                top: ChatVoiceTokens.waveformTop,
                height: ChatVoiceTokens.waveformHeight,
                child: preparing
                    ? const SizedBox()
                    : ChatVoiceWaveform(
                        key: const ValueKey('chat-voice-waveform'),
                        levels: levels,
                        color: activeZone == ChatVoiceReleaseZone.cancel
                            ? palette.danger
                            : palette.accent,
                      ),
              ),
              _control(context, palette,
                  center: layout.cancelCenter,
                  kind: ChatVoiceReleaseZone.cancel,
                  activeZone: activeZone),
              _control(context, palette,
                  center: layout.mainCenter,
                  kind: ChatVoiceReleaseZone.send,
                  activeZone: activeZone),
              if (allowConvert)
                _control(context, palette,
                    center: layout.convertCenter,
                    kind: ChatVoiceReleaseZone.convertText,
                    activeZone: activeZone),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, ChatVoiceControlsLayout layout,
      ChatVoicePalette palette, ChatVoiceReleaseZone activeZone) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (safeSeconds % 60).toString().padLeft(2, '0');
    final status = preparing
        ? '准备中…'
        : switch (activeZone) {
            ChatVoiceReleaseZone.send => '正在录音',
            ChatVoiceReleaseZone.cancel => '松开取消',
            ChatVoiceReleaseZone.convertText => '松开转文字',
          };
    final color = switch (activeZone) {
      ChatVoiceReleaseZone.cancel => palette.danger,
      ChatVoiceReleaseZone.convertText => palette.selectedText,
      ChatVoiceReleaseZone.send => palette.secondary,
    };
    return Positioned(
      left: ChatVoiceTokens.horizontalInset,
      right: ChatVoiceTokens.horizontalInset,
      top: layout.statusTopY,
      child: Semantics(
        liveRegion: true,
        excludeSemantics: true,
        label: '$status，已录制 $safeSeconds 秒',
        child: Row(children: [
          if (preparing) ...[
            _loading(context,
                color: color, radius: ChatVoiceTokens.headerSpinnerRadius),
            const SizedBox(width: ChatVoiceTokens.headerGap),
          ],
          Expanded(
              child: Text(
            status,
            key: const ValueKey('chat-voice-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: ChatVoiceTokens.hintFontSize,
                height: ChatVoiceTokens.textLineHeight,
                fontWeight: FontWeight.w500,
                color: color),
          )),
          const SizedBox(width: ChatVoiceTokens.durationGap),
          Text(
            '$minutes:$remainder',
            key: const ValueKey('chat-voice-duration'),
            style: TextStyle(
              fontSize: ChatVoiceTokens.durationFontSize,
              height: ChatVoiceTokens.textLineHeight,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: palette.text,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _control(BuildContext context, ChatVoicePalette palette,
      {required Offset center,
      required ChatVoiceReleaseZone kind,
      required ChatVoiceReleaseZone activeZone}) {
    final isSend = kind == ChatVoiceReleaseZone.send;
    final active = kind == activeZone;
    final color =
        kind == ChatVoiceReleaseZone.cancel ? palette.danger : palette.accent;
    final selectedLabelColor = kind == ChatVoiceReleaseZone.cancel
        ? palette.danger
        : palette.selectedText;
    final label = switch (kind) {
      ChatVoiceReleaseZone.cancel => '取消',
      ChatVoiceReleaseZone.send => '发送',
      ChatVoiceReleaseZone.convertText => '转文字',
    };
    final icon = switch (kind) {
      ChatVoiceReleaseZone.cancel => Icons.close_rounded,
      ChatVoiceReleaseZone.send =>
        preparing ? Icons.mic_rounded : Icons.arrow_upward_rounded,
      ChatVoiceReleaseZone.convertText => Icons.text_fields_rounded,
    };
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ChatVoiceTokens.stateAnimation;
    return Positioned(
      left: center.dx - ChatVoiceTokens.controlLabelWidth / 2,
      top: center.dy - ChatVoiceTokens.micSize / 2,
      width: ChatVoiceTokens.controlLabelWidth,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: ChatVoiceTokens.micSize,
          child: Center(
              child: Semantics(
            button: true,
            label: label,
            selected: active,
            enabled: !preparing || kind == ChatVoiceReleaseZone.cancel,
            child: AnimatedContainer(
              key: ValueKey('chat-voice-control-${kind.name}'),
              duration: duration,
              curve: Curves.easeOut,
              width:
                  isSend ? ChatVoiceTokens.micSize : ChatVoiceTokens.sideSize,
              height:
                  isSend ? ChatVoiceTokens.micSize : ChatVoiceTokens.sideSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSend
                    ? (active
                        ? palette.accent
                        : palette.selectedSurface(palette.accent))
                    : active
                        ? palette.selectedSurface(color)
                        : palette.controlSurface,
                border: isSend
                    ? null
                    : Border.all(
                        color: active ? color : palette.border,
                        width: ChatVoiceTokens.borderWidth,
                      ),
              ),
              child: Icon(
                icon,
                size: isSend
                    ? ChatVoiceTokens.micIconSize
                    : ChatVoiceTokens.iconSize,
                color: isSend
                    ? (active ? palette.onAccent : palette.accent)
                    : active
                        ? color
                        : palette.text,
              ),
            ),
          )),
        ),
        const SizedBox(height: ChatVoiceTokens.controlLabelGap),
        ExcludeSemantics(
            child: Text(
          label,
          key: ValueKey('chat-voice-control-label-${kind.name}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: ChatVoiceTokens.controlFontSize,
              height: ChatVoiceTokens.controlLineHeight,
              color: active ? selectedLabelColor : palette.secondary),
        )),
      ]),
    );
  }
}

Widget _loading(BuildContext context,
        {required Color color, required double radius}) =>
    CupertinoActivityIndicator(
      radius: radius,
      color: color,
      animating: !MediaQuery.disableAnimationsOf(context),
    );
