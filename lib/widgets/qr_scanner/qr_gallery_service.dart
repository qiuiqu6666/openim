import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:zxing2/qrcode.dart';

/// Album selection and QR image recognition, independent of QR business data.
class QrGalleryService {
  const QrGalleryService();

  Future<String?> pickImage() async {
    final selected = await ImagePicker().pickImage(source: ImageSource.gallery);
    return selected?.path;
  }

  Future<String?> readCode(String path) {
    if (path.trim().isEmpty) return Future.value(null);
    return compute(_readQrImage, path, debugLabel: 'qr_gallery');
  }
}

String? _readQrImage(String path) {
  try {
    final decoded = image.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) return null;
    final original = image.bakeOrientation(decoded);
    final longestSide = math.max(original.width, original.height);
    // Try a camera-sized image first. A larger fallback retains small codes in
    // screenshots, while bounding the pixel buffers used by the QR decoder.
    final sizes = longestSide > 2048 ? [2048, 4096] : [longestSide];
    for (final size in sizes) {
      final candidate = longestSide <= size
          ? original
          : image.copyResize(
              original,
              width: math.max(1, (original.width * size / longestSide).round()),
              height:
                  math.max(1, (original.height * size / longestSide).round()),
              interpolation: image.Interpolation.average,
            );
      var rotated = candidate;
      for (var turn = 0; turn < 4; turn++) {
        final source = _luminanceSource(rotated);
        for (final polarity in [source, source.invert()]) {
          try {
            final hints = DecodeHints()
              ..put(DecodeHintType.tryHarder)
              ..put(DecodeHintType.characterSet, 'UTF-8');
            final result = QRCodeReader().decode(
              BinaryBitmap(HybridBinarizer(polarity)),
              hints: hints,
            );
            if (result.text.isNotEmpty) return _qrText(result);
          } on ReaderException {
            // Continue with the alternate polarity or orientation.
          }
        }
        if (turn < 3) rotated = image.copyRotate(rotated, angle: 90);
      }
    }
    return null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on image.ImageException {
    return null;
  } on RangeError {
    // Some image format probes read a header before rejecting truncated input.
    return null;
  }
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

RGBLuminanceSource _luminanceSource(image.Image source) {
  final pixels = Int32List(source.width * source.height);
  var offset = 0;
  for (final pixel in source) {
    // Transparent exports should retain a white quiet zone, as on the page.
    final alpha = pixel.aNormalized;
    final red = (255 * (pixel.rNormalized * alpha + 1 - alpha)).round();
    final green = (255 * (pixel.gNormalized * alpha + 1 - alpha)).round();
    final blue = (255 * (pixel.bNormalized * alpha + 1 - alpha)).round();
    pixels[offset++] = (red << 16) | (green << 8) | blue;
  }
  return RGBLuminanceSource(source.width, source.height, pixels);
}
