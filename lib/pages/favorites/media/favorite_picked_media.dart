import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../services/favorite_repository.dart';

/// Upload declarations describe the selected original, including files whose
/// temporary path lost its extension. The server remains the final decoder.
class FavoritePickedMedia {
  const FavoritePickedMedia(
      {required this.filePath, required this.fileName, required this.mimeType});
  final String filePath, fileName, mimeType;

  static Future<FavoritePickedMedia> inspect(String filePath,
      {required FavoriteKind kind,
      String? fileName,
      String? reportedMimeType}) async {
    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      throw const FavoriteApiException(
          'ORIGINAL_UNAVAILABLE', '无法读取收藏原件，请重新选择');
    }
    final name = p.basename((fileName ?? filePath).replaceAll('\\', '/'));
    final handle = await file.open();
    late List<int> header;
    try {
      header = await handle.read(512);
    } finally {
      await handle.close();
    }
    final reported = reportedMimeType?.trim().toLowerCase();
    final named = lookupMimeType(name);
    final detected = lookupMimeType('', headerBytes: header);
    // The same ISO media container can hold an audio-only M4A original.
    final audioContainer = detected == 'video/mp4' &&
        (named == 'audio/mp4' || reported == 'audio/mp4');
    final mime = audioContainer
        ? 'audio/mp4'
        : detected ??
            lookupMimeType(filePath) ??
            named ??
            (reported != null &&
                    RegExp(r'^[a-z0-9.+-]+/[a-z0-9.+-]+$').hasMatch(reported)
                ? reported
                : null) ??
            'application/octet-stream';
    final prefix = switch (kind) {
      FavoriteKind.image => 'image/',
      FavoriteKind.video => 'video/',
      FavoriteKind.audio => 'audio/',
      _ => null,
    };
    if (prefix != null && !mime.startsWith(prefix)) {
      throw const FavoriteApiException(
          'UNSUPPORTED_MEDIA', '原件格式与收藏类型不一致，请重新选择');
    }
    return FavoritePickedMedia(
        filePath: filePath, fileName: name, mimeType: mime);
  }
}
