import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as image;
import 'package:zxing2/qrcode.dart';
import 'qr_gallery_result.dart';

/// Compatibility fallback when the packaged native engine is unavailable.
/// Position points here are ZXing finder points, not native outer corners.
List<QrGalleryCode> decodeQrDart(image.Image bitmap) {
  final pixels = Int32List(bitmap.width * bitmap.height);
  var i = 0;
  for (final p in bitmap) {
    final v = p.r.toInt();
    pixels[i++] = (v << 16) | (v << 8) | v;
  }
  final source = RGBLuminanceSource(bitmap.width, bitmap.height, pixels);
  for (final polarity in [source, source.invert()]) {
    for (final binarizer in <Binarizer>[
      HybridBinarizer(polarity),
      GlobalHistogramBinarizer(polarity)
    ]) {
      try {
        final result = QRCodeReader().decode(BinaryBitmap(binarizer),
            hints: DecodeHints()
              ..put(DecodeHintType.tryHarder)
              ..put(DecodeHintType.characterSet, 'UTF-8'));
        if (result.text.isNotEmpty) {
          return [
            QrGalleryCode(
                text: _qrText(result),
                corners:
                    result.resultPoints.map((p) => Offset(p.x, p.y)).toList())
          ];
        }
      } on ReaderException {/* Try the next established binarizer. */}
    }
  }
  return [];
}

String _qrText(Result result) {
  var text = result.text;
  if (!text.contains('\uFFFD')) return text;
  final segments = result.resultMetadata[ResultMetadataType.byteSegments];
  if (segments is! List<Int8List>) return text;
  var start = 0;
  for (final segment in segments) {
    // ZXing 0.2.4 passes signed Int8List values to its UTF-8 codec. Repair each
    // affected byte segment without dropping other numeric/alphanumeric modes.
    final malformed = utf8.decode(segment, allowMalformed: true);
    final index = text.indexOf(malformed, start);
    if (index < 0) continue;
    try {
      final decoded = utf8.decode(segment.map((byte) => byte & 0xff).toList());
      text = text.replaceRange(index, index + malformed.length, decoded);
      start = index + decoded.length;
    } on FormatException {
      // A QR using another declared encoding retains the decoder's own text.
    }
  }
  return text;
}
