import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Explicitly identifies a real top crop. Legacy thumbnails keep their original
/// interpretation; dimensions alone cannot distinguish a top crop from a fit.
abstract final class ChatPicturePreviewMetadata {
  static const key = '99chatPicturePreview';
  static const heightRatio = 1.8;
  static const maxWidth = 480;

  static Map<String, dynamic>? _extra(String? value) {
    if (value == null || value.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static bool canAnnotate(String? extra) => _extra(extra) != null;

  static String? withTopCrop(String? extra,
      {required String sourceURL, required String previewURL}) {
    final data = _extra(extra);
    if (data == null) return null;
    return jsonEncode({
      ...data,
      key: {
        'version': 1,
        'kind': 'topCrop',
        'sourceURL': sourceURL,
        'previewURL': previewURL,
      },
    });
  }

  static PictureInfo? topCrop(Message message) {
    final data = _extra(message.ex)?[key];
    final picture = message.pictureElem;
    final preview = picture?.snapshotPicture;
    if (data is! Map ||
        data['version'] != 1 ||
        data['kind'] != 'topCrop' ||
        data['sourceURL'] is! String ||
        (data['sourceURL'] as String).trim().isEmpty ||
        preview?.url?.isNotEmpty != true ||
        data['previewURL'] != preview!.url ||
        data['sourceURL'] != picture?.sourcePicture?.url ||
        preview.url == picture?.sourcePicture?.url ||
        (preview.width ?? 0) <= 0 ||
        preview.width! > maxWidth ||
        (preview.height ?? 0) <= 0 ||
        (preview.height! - preview.width! * heightRatio).abs() > 1) {
      return null;
    }
    return preview;
  }
}
