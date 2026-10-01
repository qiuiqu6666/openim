import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

class ChatPictureGallery {
  const ChatPictureGallery({required this.sources, required this.initialIndex});

  final List<MediaSource> sources;
  final int initialIndex;

  static ChatPictureGallery fromMessages(
    Iterable<Message> messages,
    Message selected,
  ) {
    final sources = <MediaSource>[];
    var initialIndex = -1;

    void add(Message message) {
      final video = message.contentType == MessageType.video;
      if (!video && message.contentType != MessageType.picture) return;
      final picture = message.pictureElem;
      if (video ? message.videoElem == null : picture == null) return;

      final path = video ? message.videoElem?.videoPath : picture?.sourcePath;
      final file = path != null && path.isNotEmpty && File(path).existsSync()
          ? File(path)
          : null;
      final url = video
          ? _firstUrl([message.videoElem?.videoUrl])
          : _firstUrl([
              picture?.sourcePicture?.url,
              picture?.bigPicture?.url,
              picture?.snapshotPicture?.url,
            ]);
      if (file == null && url == null) return;

      if (identical(message, selected) ||
          (selected.clientMsgID?.isNotEmpty == true &&
              message.clientMsgID == selected.clientMsgID)) {
        initialIndex = sources.length;
      }
      sources.add(MediaSource(
        url: url,
        thumbnail: video
            ? message.videoElem?.snapshotUrl ?? ''
            : _firstUrl([picture?.snapshotPicture?.url, url]) ?? '',
        isVideo: video,
        file: file,
        tag: message.clientMsgID,
        senderName: message.senderNickname,
        sentAt: message.sendTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(message.sendTime!),
      ));
    }

    for (final message in messages) {
      add(message);
    }
    if (initialIndex < 0) {
      add(selected);
      if (initialIndex < 0) {
        return const ChatPictureGallery(sources: [], initialIndex: 0);
      }
    }
    return ChatPictureGallery(sources: sources, initialIndex: initialIndex);
  }

  static String? _firstUrl(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }
}
