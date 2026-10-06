import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/media/favorite_picked_media.dart';
import 'package:openim/services/favorite_repository.dart';

void main() {
  late Directory directory;
  setUp(() async =>
      directory = await Directory.systemTemp.createTemp('favorite-pick-'));
  tearDown(() async => directory.delete(recursive: true));
  Future<String> file(String name, List<int> bytes) async =>
      (await File('${directory.path}/$name').writeAsBytes(bytes)).path;

  test('extensionless PNG original retains its real MIME and file name',
      () async {
    final path = await file('picker-cache', [137, 80, 78, 71, 13, 10, 26, 10]);
    final picked = await FavoritePickedMedia.inspect(path,
        kind: FavoriteKind.image, fileName: '照片.png');
    expect(picked.filePath, path);
    expect(picked.fileName, '照片.png');
    expect(picked.mimeType, 'image/png');
  });

  test('HEIC original is declared as HEIC rather than the thumbnail JPEG',
      () async {
    final path = await file('original-cache',
        [0, 0, 0, 24, ...ascii.encode('ftypheic'), 0, 0, 0, 0]);
    final picked = await FavoritePickedMedia.inspect(path,
        kind: FavoriteKind.image,
        fileName: 'original.HEIC',
        reportedMimeType: 'image/jpeg');
    expect(picked.mimeType, 'image/heic');
    expect(picked.fileName, 'original.HEIC');
  });

  test('file MIME is sniffed from the original rather than its misleading name',
      () async {
    final path = await file('cache', ascii.encode('%PDF-1.7'));
    final picked = await FavoritePickedMedia.inspect(path,
        kind: FavoriteKind.file, fileName: 'photo.jpg');
    expect(picked.mimeType, 'application/pdf');
    await expectLater(
        FavoritePickedMedia.inspect(path,
            kind: FavoriteKind.image, fileName: 'photo.jpg'),
        throwsA(isA<FavoriteApiException>()
            .having((value) => value.code, 'code', 'UNSUPPORTED_MEDIA')));
  });

  test('audio-only M4A keeps the correct declared MIME', () async {
    final path = await file(
        'cache', [0, 0, 0, 24, ...ascii.encode('ftypisom'), 0, 0, 0, 0]);
    final picked = await FavoritePickedMedia.inspect(path,
        kind: FavoriteKind.audio, fileName: 'voice.m4a');
    expect(picked.mimeType, 'audio/mp4');
  });

  test(
      'unknown ordinary files remain binary, and missing originals fail before upload',
      () async {
    final path = await file('cache', [1, 2, 3]);
    final picked = await FavoritePickedMedia.inspect(path,
        kind: FavoriteKind.file, fileName: '../backup.custom');
    expect(picked.mimeType, 'application/octet-stream');
    expect(picked.fileName, 'backup.custom');
    await expectLater(
        FavoritePickedMedia.inspect('$path-missing', kind: FavoriteKind.file),
        throwsA(isA<FavoriteApiException>()));
  });
}
