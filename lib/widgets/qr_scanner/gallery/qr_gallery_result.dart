import 'dart:ui';

enum QrGalleryStatus {
  success,
  noCode,
  invalidImage,
  tooLarge,
  timeout,
  cancelled,
  unavailable
}

/// Coordinates are pixels in the EXIF-corrected original, never the thumbnail.
class QrGalleryCode {
  const QrGalleryCode(
      {required this.text, this.format = 'QR_CODE', this.corners = const []});
  final String text;
  final String format;
  final List<Offset> corners;
  Rect? get bounds => corners.isEmpty
      ? null
      : Rect.fromLTRB(
          corners.map((p) => p.dx).reduce((a, b) => a < b ? a : b),
          corners.map((p) => p.dy).reduce((a, b) => a < b ? a : b),
          corners.map((p) => p.dx).reduce((a, b) => a > b ? a : b),
          corners.map((p) => p.dy).reduce((a, b) => a > b ? a : b));
}

class QrGalleryResult {
  const QrGalleryResult(this.status,
      {this.codes = const [],
      this.width = 0,
      this.height = 0,
      this.passes = 0,
      this.elapsedMs = 0,
      this.partial = false,
      this.engine = 'none'});
  final QrGalleryStatus status;
  final List<QrGalleryCode> codes;
  final int width, height, passes, elapsedMs;
  final bool partial;
  final String engine;
}
