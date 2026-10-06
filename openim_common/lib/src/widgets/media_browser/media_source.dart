import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../config.dart';
import '../../utils/media/openim_media_url.dart';

class MediaSource {
  final String? url;
  final String thumbnail;
  final File? file;
  final Uint8List? bytes;
  final bool isVideo;
  final String? tag;
  final String? senderName;
  final DateTime? sentAt;
  final bool loading;
  final VoidCallback? onRetry;

  MediaSource(
      {required String thumbnail,
      String? url,
      this.file,
      this.bytes,
      this.isVideo = false,
      this.tag,
      this.senderName,
      this.sentAt,
      this.loading = false,
      this.onRetry})
      : thumbnail =
            OpenIMMediaUrl.resolve(thumbnail, imApiUrl: Config.imApiUrl),
        url = url == null
            ? null
            : OpenIMMediaUrl.resolve(url, imApiUrl: Config.imApiUrl);
}
