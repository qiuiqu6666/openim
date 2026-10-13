import 'dart:convert';
import 'dart:io';
import 'package:openim/widgets/qr_scanner/qr_gallery_service.dart';
import 'package:openim/widgets/qr_scanner/gallery/qr_gallery_runner.dart';
import 'fixture_data.dart';

Future<Map<String, Object?>> runQrTaskProbe() async {
  final directory = await Directory.systemTemp.createTemp('qr-probe-');
  final fixtures = jsonDecode(qrFixtureJson) as Map;
  final long = File('${directory.path}/long.png');
  final small = File('${directory.path}/small.png');
  await long.writeAsBytes(base64Decode(fixtures['long']['data']));
  await small.writeAsBytes(base64Decode(fixtures['size-100']['data']));
  Future<int> temporaryCount() async => (await Directory.systemTemp
          .list()
          .toList())
      .where((e) =>
          e.path.split(Platform.pathSeparator).last.startsWith('qr-local-'))
      .length;
  final before = await temporaryCount();
  try {
    const service = QrGalleryService();
    final token = QrGalleryCancellation();
    final pending = service.scan(long.path, cancellation: token);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final cancelWatch = Stopwatch()..start();
    token.cancel();
    final cancelled = await pending;
    final cancelMs = cancelWatch.elapsedMilliseconds;
    final replacements = List.generate(8, (_) => service.scan(small.path));
    final results = await Future.wait(replacements);
    final timeout =
        await service.scan(long.path, timeout: const Duration(milliseconds: 1));
    await QrGalleryRunner.settled;
    final rssBefore = ProcessInfo.currentRss;
    var repeatOk = true;
    for (var i = 0; i < 20; i++) {
      final value = await service.scan(small.path);
      repeatOk = repeatOk && value.status == QrGalleryStatus.success;
    }
    await QrGalleryRunner.settled;
    final after = await temporaryCount();
    return {
      'passed': cancelled.status == QrGalleryStatus.cancelled &&
          cancelMs < 500 &&
          results.take(7).every((r) => r.status == QrGalleryStatus.cancelled) &&
          results.last.status == QrGalleryStatus.success &&
          timeout.status == QrGalleryStatus.timeout &&
          repeatOk &&
          after == before,
      'cancelMs': cancelMs,
      'replacements': 8,
      'repeatScans': 20,
      'temporaryFilesDelta': after - before,
      'repeatRssDeltaBytes': ProcessInfo.currentRss - rssBefore
    };
  } finally {
    await QrGalleryRunner.settled;
    await directory.delete(recursive: true);
  }
}
