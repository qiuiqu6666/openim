import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/qr_scanner/qr_gallery_service.dart';
import 'package:openim/widgets/qr_scanner/gallery/qr_gallery_runner.dart';
import '../../support/qr_gallery/fixture_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String path;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('qr-task-test-');
    path = '${dir.path}/fixture.png';
    await File(path)
        .writeAsBytes(base64Decode(jsonDecode(qrFixtureJson)['long']['data']));
  });
  tearDown(() async {
    await QrGalleryRunner.settled;
    await dir.delete(recursive: true);
  });
  test('explicit cancellation returns promptly and drains resources', () async {
    final token = QrGalleryCancellation();
    final pending = const QrGalleryService().scan(path, cancellation: token);
    token.cancel();
    expect((await pending).status, QrGalleryStatus.cancelled);
  });
  test('replacements keep only the newest task eligible to return a code',
      () async {
    const service = QrGalleryService();
    final results = List.generate(10, (_) => service.scan(path));
    final values = await Future.wait(results);
    expect(values.take(9).every((r) => r.status == QrGalleryStatus.cancelled),
        isTrue);
    expect(values.last.status, QrGalleryStatus.success);
  });
  test('deadline is reported as timeout, not an unrecognized image', () async {
    final value = await const QrGalleryService()
        .scan(path, timeout: const Duration(microseconds: 1));
    expect(value.status, QrGalleryStatus.timeout);
  });
  test('file byte limit is checked before decoding', () async {
    final file = await File(path).open(mode: FileMode.write);
    await file.truncate(32 * 1024 * 1024 + 1);
    await file.close();
    expect((await const QrGalleryService().scan(path)).status,
        QrGalleryStatus.tooLarge);
  });
}
