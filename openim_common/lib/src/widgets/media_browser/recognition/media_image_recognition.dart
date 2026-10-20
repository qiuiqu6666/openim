import 'package:flutter/widgets.dart';
import '../media_source.dart';

/// App-owned recognition keeps business routing out of the common viewer.
abstract final class MediaImageRecognition {
  static MediaRecognitionRequest Function(MediaSource source)? start;
}

class MediaRecognitionRequest {
  const MediaRecognitionRequest(this.result, this.cancel);
  final Future<MediaRecognitionResult> result;
  final VoidCallback cancel;
}

class MediaRecognitionResult {
  const MediaRecognitionResult(this.targets, {this.partial = false});
  final List<MediaRecognitionTarget> targets;
  final bool partial;
}

class MediaRecognitionTarget {
  const MediaRecognitionTarget({
    required this.value,
    required this.title,
    required this.copyLabel,
    this.openLabel,
    this.open,
  });
  final String value, title, copyLabel;
  final String? openLabel;
  final Future<void> Function(BuildContext context, bool Function() isActive)?
      open;
}
