import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Independent rendering fixture for the production 99chat voice panel.
///
/// Source: 99chat revision d7c3c65, Apache-2.0:
/// third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/
/// TIMUIKitTextField/tim_uikit_send_sound_message.dart (tuiBuild).
/// Theme colors come from lib/utils/theme.dart at the same revision.
///
/// This fixture intentionally does not import current voice panel widgets or
/// tokens, so pixel comparisons can expose differences in the implementation.
class Reference99ChatVoicePanel extends StatelessWidget {
  const Reference99ChatVoicePanel({
    super.key,
    required this.dark,
    required this.height,
    this.active = false,
  });

  final bool dark;
  final double height;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: dark ? const Color(0xFF101114) : Colors.white,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: active
                      ? const [Color(0xFF5A7386), Color(0xFF455A6A)]
                      : const [Color(0xFF4F6475), Color(0xFF3D4F5C)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: active ? 0.18 : 0.12),
                    blurRadius: active ? 16 : 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_rounded,
                size: 42,
                color: Color(0xFF7EEBD3),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              active ? '松开 结束' : '点击 或 长按 开始录音',
              style: TextStyle(
                fontSize: 14,
                height: 1.2,
                color: dark ? const Color(0xFF9A9CA3) : const Color(0xFF7B8491),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum Reference99ChatVoiceReleaseZone { send, cancel, convertText }

/// Independent transcription of the production recording presentation.
///
/// Source: 99chat d7c3c65, Apache-2.0, same SendSoundMessage file above:
/// _buildRecordingOverlay, _buildRecordingControlsPanel,
/// _buildRecordingStatusArea, _buildRecordingMainButton,
/// _buildRecordingSideButton, _buildWaveformBars and _RecordControlsLayout.
/// This fixture has no production imports, gesture handling or recorder state.
class Reference99ChatVoiceOverlay extends StatelessWidget {
  const Reference99ChatVoiceOverlay({
    super.key,
    required this.dark,
    required this.anchorGlobal,
    required this.zone,
    this.amplitude = 0,
    this.phase = 0,
    this.allowConvert = true,
  });

  /// The recording presentation is intentionally dark in both themes.
  final bool dark;
  final Offset? anchorGlobal;
  final Reference99ChatVoiceReleaseZone zone;
  final double amplitude;
  final double phase;

  /// OpenIM can omit conversion when unavailable; production 99chat shows it.
  final bool allowConvert;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screen = MediaQuery.sizeOf(context);
    final panelHeight = 248.0 + bottomInset;
    final panelTop = screen.height - panelHeight;
    final anchor = anchorGlobal;
    final layout = _ReferenceVoiceControlsLayout(
      panelSize: Size(screen.width, panelHeight),
      bottomInset: bottomInset,
      anchorCenter:
          anchor == null ? null : Offset(anchor.dx, anchor.dy - panelTop),
    );
    final activeZone =
        !allowConvert && zone == Reference99ChatVoiceReleaseZone.convertText
            ? Reference99ChatVoiceReleaseZone.send
            : zone;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.42)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: panelHeight,
            child: _controls(layout, activeZone),
          ),
        ],
      ),
    );
  }

  Widget _controls(_ReferenceVoiceControlsLayout layout,
      Reference99ChatVoiceReleaseZone activeZone) {
    final cancelActive = activeZone == Reference99ChatVoiceReleaseZone.cancel;
    final convertActive =
        activeZone == Reference99ChatVoiceReleaseZone.convertText;
    return ColoredBox(
      color: const Color(0xFF3A3D42),
      child: SizedBox(
        height: layout.panelSize.height,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _status(layout, activeZone),
            Positioned(
              left: layout.cancelCenter.dx - 56 / 2,
              top: layout.cancelCenter.dy - 56 / 2,
              child: _sideButton(
                active: cancelActive,
                activeGlowColor: const Color(0xFFE57373),
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: cancelActive ? 1 : .88),
                  size: 28,
                ),
              ),
            ),
            Positioned(
              left: layout.mainCenter.dx - (88 + 16) / 2,
              top: layout.mainCenter.dy - (88 + 16) / 2,
              child: _mainButton(
                  glowing: activeZone == Reference99ChatVoiceReleaseZone.send),
            ),
            if (allowConvert)
              Positioned(
                left: layout.convertCenter.dx - 56 / 2,
                top:
                    layout.convertCenter.dy - 56 / 2 - (convertActive ? 22 : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (convertActive) ...[
                      const Text('转文字',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.1)),
                      const SizedBox(height: 6),
                    ],
                    _sideButton(
                      active: convertActive,
                      activeGlowColor: const Color(0xFF7EEBD3),
                      child: Text('文',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.white
                                .withValues(alpha: convertActive ? 1 : .88),
                          )),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _status(_ReferenceVoiceControlsLayout layout,
      Reference99ChatVoiceReleaseZone activeZone) {
    switch (activeZone) {
      case Reference99ChatVoiceReleaseZone.cancel:
        return Positioned(
          left: layout.cancelCenter.dx - 36,
          top: layout.statusTopY,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFFE07A7A),
                  borderRadius: BorderRadius.circular(14)),
              child: _waveform(
                  barCount: 5,
                  color: Colors.white,
                  maxHeight: 26,
                  barWidth: 2.8),
            ),
            const SizedBox(height: 10),
            const Text('松开取消',
                style: TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.1)),
          ]),
        );
      case Reference99ChatVoiceReleaseZone.convertText:
        return Positioned(
          left: 20,
          right: 20,
          top: layout.statusTopY,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
                color: const Color(0xFF95EC69),
                borderRadius: BorderRadius.circular(56 / 2)),
            child: Row(children: [
              const Text('松开后转文字',
                  style: TextStyle(
                    color: Color(0xFF2E6B38),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              _waveform(
                  barCount: 7, color: const Color(0xFF2E2E2E), maxHeight: 26),
            ]),
          ),
        );
      case Reference99ChatVoiceReleaseZone.send:
        return Positioned(
          left: layout.mainCenter.dx - 56 / 2,
          top: layout.statusTopY,
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFF95EC69),
                borderRadius: BorderRadius.circular(14)),
            child: _waveform(
                barCount: 5,
                color: const Color(0xFF2E2E2E),
                maxHeight: 26,
                barWidth: 2.8),
          ),
        );
    }
  }

  Widget _sideButton(
          {required bool active,
          required Widget child,
          Color? activeGlowColor}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? (activeGlowColor ?? const Color(0xFF5A5F66))
              : const Color(0xFF5A5F66),
          border: Border.all(
            color: active
                ? (activeGlowColor ?? const Color(0xFF6E747C))
                : const Color(0xFF6E747C),
            width: active ? 2.5 : 1.5,
          ),
          boxShadow: active && activeGlowColor != null
              ? [
                  BoxShadow(
                    color: activeGlowColor.withValues(alpha: .75),
                    blurRadius: 18,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: child,
      );

  Widget _mainButton({required bool glowing}) => Container(
        width: 88 + 16,
        height: 88 + 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: glowing
              ? [
                  BoxShadow(
                    color: const Color(0xFF7EEBD3).withValues(alpha: .55),
                    blurRadius: 22,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4A5C6B).withValues(alpha: .92),
            border: Border.all(
              color:
                  glowing ? const Color(0xFF7EEBD3) : const Color(0xFF5A6D7C),
              width: glowing ? 3 : 2,
            ),
          ),
          child: const CustomPaint(painter: _ReferenceDiamondDotsPainter()),
        ),
      );

  Widget _waveform(
      {required int barCount,
      required Color color,
      double maxHeight = 24,
      double barWidth = 3}) {
    final normalized = math.max(0.0, math.min(amplitude, 1.0));
    final center = (barCount - 1) / 2;
    final bars = List<double>.generate(barCount, (index) {
      final edgeFade = 1.0 - ((index - center).abs() / center).clamp(0.0, 1.0);
      if (edgeFade < .18) return .14;
      final base = .18 + .38 * math.sin(index * .58 + phase * .35);
      final pulse =
          normalized * edgeFade * (.5 + .5 * math.sin(index * .92 + phase));
      return math.max(.14, math.min(1.0, math.max(base, pulse)));
    });
    return SizedBox(
      height: maxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(
            barCount,
            (index) => Container(
                  width: barWidth,
                  height: math.max(4.0, maxHeight * bars[index]),
                  margin: EdgeInsets.symmetric(horizontal: barWidth * .45),
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(barWidth / 2)),
                )),
      ),
    );
  }
}

class _ReferenceVoiceControlsLayout {
  const _ReferenceVoiceControlsLayout(
      {required this.panelSize, required this.bottomInset, this.anchorCenter});

  final Size panelSize;
  final double bottomInset;
  final Offset? anchorCenter;

  Offset get mainCenter =>
      anchorCenter ??
      Offset(panelSize.width / 2, panelSize.height - bottomInset - 92);
  Offset get cancelCenter =>
      Offset(mainCenter.dx - 88 / 2 - 48 - 56 / 2, mainCenter.dy);
  Offset get convertCenter =>
      Offset(mainCenter.dx + 88 / 2 + 48 + 56 / 2, mainCenter.dy);
  double get statusTopY => mainCenter.dy - 88 / 2 - 88;
}

class _ReferenceDiamondDotsPainter extends CustomPainter {
  const _ReferenceDiamondDotsPainter();

  static const offsets = [
    Offset(0, -24),
    Offset(-12, -12),
    Offset(12, -12),
    Offset(-24, 0),
    Offset.zero,
    Offset(24, 0),
    Offset(-12, 12),
    Offset(12, 12),
    Offset(0, 24),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2C3844);
    final center = Offset(size.width / 2, size.height / 2);
    for (final offset in offsets) {
      canvas.drawCircle(center + offset, 3.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
