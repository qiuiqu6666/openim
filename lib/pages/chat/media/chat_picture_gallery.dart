import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../stickers/sticker_video_message.dart';

class ChatPictureGallery {
  ChatPictureGallery({
    required List<MediaSource> sources,
    required this.initialIndex,
    List<Message> messages = const [],
  })  : sources = List.unmodifiable(sources),
        _messages = List.unmodifiable(messages.map(_snapshot));

  ChatPictureGallery._captured(
      {required this.sources,
      required this.initialIndex,
      required List<Message> messages})
      : _messages = List.unmodifiable(messages);

  final List<MediaSource> sources;
  final int initialIndex;
  final List<Message> _messages;

  /// Browser indexes refer to this gallery's snapshot, not a changing timeline.
  /// A missing identity never falls back to the originally tapped message.
  Message? messageAt(int index) {
    if (index < 0 || index >= sources.length || index >= _messages.length) {
      return null;
    }
    final message = _messages[index];
    final id = message.clientMsgID;
    if (id == null || id.trim().isEmpty || sources[index].tag != id) {
      return null;
    }
    return _snapshot(message);
  }

  static Future<ChatPictureGallery> fromMessages(
    Iterable<Message> messages,
    Message selected,
  ) async {
    // Capture both ordering and mutable SDK content before file checks yield.
    final selectedID = selected.clientMsgID;
    final selectedSnapshot = _snapshot(selected);
    final snapshot = [
      for (final message in messages)
        if (message.contentType == MessageType.picture ||
            message.contentType == MessageType.video)
          (
            message: _snapshot(message),
            selected: identical(message, selected) ||
                (selectedID?.isNotEmpty == true &&
                    message.clientMsgID == selectedID),
          ),
    ];
    final sources = <MediaSource>[];
    final mappedMessages = <Message>[];
    var initialIndex = -1;
    final addedIDs = <String>{};

    Future<void> add(Message message, {required bool isSelected}) async {
      if (isStickerVideoMessage(message)) return;
      final video = message.contentType == MessageType.video;
      if (!video && message.contentType != MessageType.picture) return;
      final picture = message.pictureElem;
      if (video ? message.videoElem == null : picture == null) return;

      final path = video ? message.videoElem?.videoPath : picture?.sourcePath;
      final file = path != null && path.isNotEmpty ? File(path) : null;
      // The viewer validates local files only when their page is opened.
      final url = video
          ? _firstUrl([message.videoElem?.videoUrl])
          : _firstUrl([
              picture?.sourcePicture?.url,
              picture?.bigPicture?.url,
              picture?.snapshotPicture?.url,
            ]);
      if (file == null && url == null) return;
      final id = message.clientMsgID;
      if (id != null && id.isNotEmpty && !addedIDs.add(id)) return;

      if (isSelected) {
        initialIndex = sources.length;
      }
      sources.add(MediaSource(
        url: url,
        previewUrl: video ? null : _previewUrl(picture, url),
        deferOriginal: !video,
        thumbnail: video
            ? message.videoElem?.snapshotUrl ?? ''
            : _firstUrl([
                  picture?.snapshotPicture?.url,
                  if (url != null)
                    OpenIMMediaUrl.thumbnail(url, width: 640, height: 640)
                ]) ??
                '',
        isVideo: video,
        file: file,
        tag: message.clientMsgID,
        senderName: message.senderNickname,
        sentAt: message.sendTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(message.sendTime!),
      ));
      mappedMessages.add(message);
    }

    for (final entry in snapshot) {
      await add(entry.message, isSelected: entry.selected);
    }
    if (initialIndex < 0) {
      await add(selectedSnapshot, isSelected: true);
      if (initialIndex < 0) {
        return ChatPictureGallery(sources: [], initialIndex: 0);
      }
    }
    return ChatPictureGallery._captured(
        sources: List.unmodifiable(sources),
        messages: mappedMessages,
        initialIndex: initialIndex);
  }

  static String? _firstUrl(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String? _previewUrl(PictureElem? picture, String? original) {
    final big = _firstUrl([picture?.bigPicture?.url]);
    if (big != null && big != original) return big;
    if (original != null) {
      final resized =
          OpenIMMediaUrl.thumbnail(original, width: 1600, height: 1600);
      if (resized != original) return resized;
    }
    return _firstUrl([picture?.snapshotPicture?.url, original]);
  }

  static Message _snapshot(Message message) =>
      Message.fromJson(_copy(message.toJson()) as Map<String, dynamic>);

  static Object? _copy(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key as String: _copy(entry.value),
      };
    }
    if (value is List) return value.map(_copy).toList();
    return value;
  }
}
