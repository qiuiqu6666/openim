import 'package:flutter/material.dart';

import '../../player/utils/format_duration.dart';

/// A compact voice recording widget that shows a record/stop button,
/// animated waveform, timer, and optional cancel hints.
///
/// This widget is highly customizable and is intended to be used in
/// voice recording features.
///
/// Example usage:
/// ```dart
/// VoiceCompactStyle(
///   isRecording: true,
///   showCancelHint: true,
///   showSwipeLeftToCancel: true,
///   dragToLeftText: 'Swipe left to cancel',
///   dragToLeftTextStyle: TextStyle(color: Colors.red),
///   showTimerText: true,
///   isCancelled: false,
///   cancelDoneText: 'Cancelled',
///   timerTextStyle: TextStyle(color: Colors.white),
///   seconds: 30,
///   cancelHintColor: Colors.red,
///   timerFontSize: 14,
///   iconSize: 50,
///   backgroundColorSecond: Colors.grey,
///   backgroundColorFirst: Colors.red,
///   stopRecordingWidget: Icon(Icons.stop),
///   startRecordingWidget: Icon(Icons.mic),
///   iconColor: Colors.white,
///   containerColor: Colors.black12,
///   borderColor: Colors.grey,
///   borderRadius: 12,
///   idleWavesColor: Colors.grey,
///   recordingWavesColor: Colors.red,
///   speed: Duration(milliseconds: 200),
/// )
/// ```
class VoiceCompactStyle extends StatelessWidget {
  /// Creates a [VoiceCompactStyle] widget.
  const VoiceCompactStyle({
    super.key,
    this.idleText,
    required this.isRecording,
    required this.showCancelHint,
    required this.showSwipeLeftToCancel,
    required this.dragToLeftText,
    required this.dragToLeftTextStyle,
    required this.showTimerText,
    required this.isCancelled,
    required this.cancelDoneText,
    required this.timerTextStyle,
    required this.seconds,
    required this.cancelHintColor,
    required this.timerFontSize,
    required this.iconSize,
    required this.backgroundColorSecond,
    required this.backgroundColorFirst,
    required this.stopRecordingWidget,
    required this.startRecordingWidget,
    required this.iconColor,
    required this.containerColor,
    required this.borderColor,
    required this.borderRadius,
    required this.idleWavesColor,
    required this.recordingWavesColor,
    required this.speed,
  });

  final String? idleText;

  /// Whether recording is in progress.
  final bool isRecording;

  /// Whether to show the cancel hint below the UI.
  final bool showCancelHint;

  /// Whether to show the "swipe left to cancel" instruction.
  final bool showSwipeLeftToCancel;

  /// Text to show for the swipe left to cancel hint.
  final String dragToLeftText;

  /// Custom style for [dragToLeftText].
  final TextStyle? dragToLeftTextStyle;

  /// Whether to show the recording timer.
  final bool showTimerText;

  /// Indicates if the recording was cancelled.
  final bool isCancelled;

  /// Text to show if recording was cancelled.
  final String cancelDoneText;

  /// Custom text style for the timer.
  final TextStyle? timerTextStyle;

  /// The number of seconds recorded.
  final int seconds;

  /// Color used for the cancel hint and timer.
  final Color cancelHintColor;

  /// Font size for the timer.
  final double timerFontSize;

  /// Size of the recording icon button.
  final double iconSize;

  /// Background color when not recording.
  final Color backgroundColorSecond;

  /// Background color when recording.
  final Color backgroundColorFirst;

  /// Custom widget to show when recording (e.g., a stop button).
  final Widget? stopRecordingWidget;

  /// Custom widget to show when not recording (e.g., a mic icon).
  final Widget? startRecordingWidget;

  /// Icon color for the mic/stop icon.
  final Color iconColor;

  /// Background color of the container.
  final Color? containerColor;

  /// Border color of the container.
  final Color? borderColor;

  /// Color of the waveform bars when idle.
  final Color? idleWavesColor;

  /// Color of the waveform bars when recording.
  final Color? recordingWavesColor;

  /// Radius of the container's border.
  final double? borderRadius;

  /// Speed of waveform animation.
  final Duration? speed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: containerColor ?? Colors.transparent,
        border: Border.all(color: borderColor ?? Colors.transparent),
        borderRadius: BorderRadius.circular(borderRadius ?? 8),
      ),
      child: Row(children: [
        Icon(isRecording ? Icons.mic : Icons.mic_none,
            size: iconSize,
            color: isRecording ? recordingWavesColor : iconColor),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          isRecording ? dragToLeftText : (idleText ?? 'Hold to record'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: dragToLeftTextStyle,
        )),
        if (isRecording && showTimerText) ...[
          const SizedBox(width: 8),
          Text(formatDurationSeconds(seconds), style: timerTextStyle),
        ],
      ]),
    );
  }
}
