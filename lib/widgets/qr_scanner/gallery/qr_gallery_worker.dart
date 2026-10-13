import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_zxing/flutter_zxing.dart' as native;
import 'package:image/image.dart' as image;

import 'qr_dart_decoder.dart';
import 'qr_gallery_result.dart';

typedef QrWorkerInput = (SendPort, String, int, int, int, int);

/// Synchronous native decoding and all pixel work belong exclusively here.
Future<void> qrGalleryWorker(QrWorkerInput input) async {
  final control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  input.$1.send(control.sendPort);
  final watch = Stopwatch()..start();
  var passes = 0;
  var width = 0, height = 0;
  var engine = 'zxing-cpp';
  final found = <QrGalleryCode>[];
  bool budget() => !cancelled && passes < 36 && watch.elapsedMilliseconds < input.$6;
  QrGalleryResult finish(QrGalleryStatus status, {bool partial = false}) =>
      QrGalleryResult(found.isNotEmpty ? QrGalleryStatus.success : status,
          codes: found,
          width: width,
          height: height,
          passes: passes,
          elapsedMs: watch.elapsedMilliseconds,
          engine: engine,
          partial: partial);
  Future<QrGalleryResult> run() async {
    final file = File(input.$2);
    if (file.lengthSync() > 32 * 1024 * 1024) {
      return finish(QrGalleryStatus.tooLarge);
    }
    final bytes = file.readAsBytesSync();
    image.Image? source;
    if (input.$3 > 0) {
      if (bytes.length != input.$3 * input.$4) {
        return finish(QrGalleryStatus.invalidImage);
      }
      source = image.Image.fromBytes(
          width: input.$3,
          height: input.$4,
          bytes: bytes.buffer,
          numChannels: 1);
      source.exif.imageIfd.orientation = input.$5;
      source = image.bakeOrientation(source);
    } else {
      final decoder = image.findDecoderForData(bytes);
      final header = decoder?.startDecode(bytes);
      if (header == null) return finish(QrGalleryStatus.invalidImage);
      if (header.width <= 0 ||
          header.height <= 0 ||
          header.width > 32768 ||
          header.height > 32768 ||
          header.width * header.height > 16 * 1024 * 1024) {
        return finish(QrGalleryStatus.tooLarge);
      }
      final decoded = decoder!.decodeFrame(0);
      if (decoded == null) return finish(QrGalleryStatus.invalidImage);
      final upright = image.bakeOrientation(decoded);
      source = image.Image(
          width: upright.width, height: upright.height, numChannels: 1);
      for (final p in upright) {
        final lum =
            .299 * p.rNormalized + .587 * p.gNormalized + .114 * p.bNormalized;
        source.setPixelR(p.x, p.y,
            (255 * (lum * p.aNormalized + 1 - p.aNormalized)).round());
      }
    }
    width = source.width;
    height = source.height;
    var nativeReady = true;
    try {
      native.zx.setLogEnabled(false);
      native.zx.version();
    } catch (_) {
      if (Platform.isAndroid || Platform.isIOS) {
        return finish(QrGalleryStatus.unavailable);
      }
      nativeReady = false;
      engine = 'zxing-dart';
    }

    Future<void> scan(image.Image candidate,
        {int left = 0,
        int top = 0,
        double scaleX = 1,
        double scaleY = 1,
        bool harder = true}) async {
      await Future<void>.delayed(Duration.zero);
      if (!budget()) return;
      passes++;
      final List<QrGalleryCode> codes;
      if (nativeReady) {
        codes = native.zx
            .readBarcodes(
                candidate.getBytes(),
                native.DecodeParams(
                  width: candidate.width,
                  height: candidate.height,
                  format: native.Format.qrCode,
                  imageFormat: native.ImageFormat.lum,
                  tryHarder: harder,
                  tryRotate: true,
                  tryInverted: true,
                  tryDownscale: false,
                  maxNumberOfSymbols: 16,
                ))
            .codes
            .where((c) => c.isValid && c.text?.isNotEmpty == true)
            .map((c) {
          final p = c.position;
          return QrGalleryCode(
              text: c.text!,
              corners: p == null
                  ? []
                  : [
                      Offset(p.topLeftX.toDouble(), p.topLeftY.toDouble()),
                      Offset(p.topRightX.toDouble(), p.topRightY.toDouble()),
                      Offset(
                          p.bottomRightX.toDouble(), p.bottomRightY.toDouble()),
                      Offset(
                          p.bottomLeftX.toDouble(), p.bottomLeftY.toDouble()),
                    ]);
        }).toList();
      } else {
        codes = decodeQrDart(candidate);
      }
      for (final code in codes) {
        final mapped = QrGalleryCode(text: code.text, corners: [
          for (final p in code.corners)
            Offset(left + p.dx * scaleX, top + p.dy * scaleY)
        ]);
        // Merge the same physical code across overlapping passes. Keep equal
        // payloads at different locations available for explicit selection.
        if (!found.any((c) =>
            c.text == mapped.text &&
            (c.bounds == null ||
                mapped.bounds == null ||
                c.bounds!.overlaps(mapped.bounds!)))) {
          found.add(mapped);
        }
        if (found.length >= 16) break;
      }
    }

    // Never downsample before the first original-resolution pass.
    // A fast-only pass can find a large code but miss a small second code.
    // Use the engine's exhaustive QR detector for the original multi-code pass.
    await scan(source);
    if (found.isNotEmpty) {
      return finish(QrGalleryStatus.success, partial: found.length >= 16);
    }
    final longest = math.max(width, height);
    for (final factor in [if (longest <= 900) 2.0, .75, .5]) {
      if (!budget()) break;
      final w = math.max(1, (width * factor).round());
      final h = math.max(1, (height * factor).round());
      await scan(
          image.copyResize(source,
              width: w, height: h, interpolation: image.Interpolation.linear),
          scaleX: width / w,
          scaleY: height / h);
      if (found.isNotEmpty) {
        return finish(QrGalleryStatus.success, partial: found.length >= 16);
      }
    }
    // Alternate global contrast can recover low-contrast and colored exports.
    if (budget()) await scan(image.normalize(source.clone(), min: 0, max: 255));
    if (found.isNotEmpty) {
      return finish(QrGalleryStatus.success, partial: found.length >= 16);
    }
    const side = 1024;
    final cw = math.min(side, width), ch = math.min(side, height);
    if (cw != width || ch != height) {
      for (final y in _offsets(height, ch)) {
        for (final x in _offsets(width, cw)) {
          if (!budget() || found.length >= 16) {
            return finish(QrGalleryStatus.timeout, partial: true);
          }
          await scan(image.copyCrop(source, x: x, y: y, width: cw, height: ch),
              left: x, top: y);
        }
      }
    }
    return finish(budget() ? QrGalleryStatus.noCode : QrGalleryStatus.timeout,
        partial: !budget());
  }

  try {
    final result = await run();
    control.close();
    Isolate.exit(input.$1, result);
  } catch (_) {
    control.close();
    Isolate.exit(input.$1, finish(QrGalleryStatus.invalidImage));
  }
}

Iterable<int> _offsets(int length, int window) sync* {
  final last = length - window;
  for (var offset = 0; offset < last; offset += window ~/ 2) {
    yield offset;
  }
  yield last;
}
