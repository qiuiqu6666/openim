import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:openim/widgets/qr_scanner/qr_gallery_service.dart';
import 'fixture_data.dart';

/// Shared desktop/native corpus; never prints decoded payloads or user paths.
Future<List<Map<String, Object?>>> runQrCorpus(
    {bool includeHeic = false}) async {
  final fixtures = jsonDecode(qrFixtureJson) as Map<String, dynamic>;
  final directory = await Directory.systemTemp.createTemp('qr-corpus-');
  final rows = <Map<String, Object?>>[];
  try {
    for (final entry in fixtures.entries) {
      // The mobile platform decoder covers HEIC and lossless WebP. The pinned
      // Dart image decoder has a known lossless WebP palette decoding failure.
      if (['heic', 'webp'].contains(entry.key) && !includeHeic) continue;
      final data = entry.value as Map;
      final file = File('${directory.path}/${entry.key}.image');
      await file.writeAsBytes(base64Decode(data['data'] as String));
      final watch = Stopwatch()..start();
      final rssBefore = ProcessInfo.currentRss;
      var peakRss = rssBefore;
      final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final rss = ProcessInfo.currentRss;
        if (rss > peakRss) peakRss = rss;
      });
      final QrGalleryResult result;
      try {
        result = await const QrGalleryService().scan(file.path);
      } finally {
        sampler.cancel();
      }
      final expected = List<String>.from(data['expected'] as List)..sort();
      final actual = result.codes.map((c) => c.text).toList()..sort();
      final positionsValid = result.codes.every((c) =>
          c.format == 'QR_CODE' &&
          c.corners.length == 4 &&
          c.corners.every((p) =>
              p.dx >= 0 &&
              p.dy >= 0 &&
              p.dx <= result.width &&
              p.dy <= result.height));
      final statusValid = expected.isNotEmpty
          ? result.status == QrGalleryStatus.success
          : entry.key == 'oversize'
              ? result.status == QrGalleryStatus.tooLarge
              : entry.key == 'corrupt'
                  ? result.status == QrGalleryStatus.invalidImage
                  : result.status == QrGalleryStatus.noCode;
      final center = data['center'] as List?;
      final orientationValid = center == null ||
          (result.codes.length == 1 &&
              (result.codes.single.bounds!.center.dx - (center[0] as num))
                      .abs() <
                  5 &&
              (result.codes.single.bounds!.center.dy - (center[1] as num))
                      .abs() <
                  5);
      rows.add({
        'case': entry.key,
        'passed': jsonEncode(actual) == jsonEncode(expected) &&
            statusValid &&
            positionsValid &&
            orientationValid,
        'status': result.status.name,
        'codes': actual.length,
        'engine': result.engine,
        'passes': result.passes,
        'elapsedMs': watch.elapsedMilliseconds,
        'width': result.width,
        'height': result.height,
        'sampledRssDeltaBytes': peakRss - rssBefore
      });
      await file.delete();
    }
  } finally {
    await directory.delete(recursive: true);
  }
  return rows;
}
